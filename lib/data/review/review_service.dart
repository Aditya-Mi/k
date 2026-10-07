import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../core/ids.dart';
import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import '../ingest/category_resolver.dart';
import '../ingest/ingestion_service.dart';
import '../ingest/unknown_sender.dart';
import '../repositories/bank_repository.dart';
import '../repositories/ledger_repository.dart';
import 'field_marks.dart';

/// A message waiting in the review queue, with the parser's best guess.
class ReviewItem {
  const ReviewItem({
    required this.raw,
    required this.text,
    required this.guess,
  });

  final RawMessage raw;

  /// Normalized text (HTML stripped, whitespace collapsed) — what formats
  /// are matched against and what marks index into.
  final String text;
  final ParseResult guess;

  /// Null while the sender is one k doesn't know (design 03f).
  String? get bankId => raw.bankId;
  bool get unknownSender => raw.bankId == null;

  /// Short reason shown on the queue card.
  String get reason {
    if (unknownSender) return 'New sender · reads like a payment';
    if (guess.missing.contains('template')) {
      return "k couldn't read this message";
    }
    if (guess.fields.amountMinor == null) return 'Amount not found';
    if (guess.fields.direction == null) return 'Paid or received unclear';
    if (guess.fields.last4 == null) return 'Account not found';
    return 'Needs a look';
  }
}

/// What the owner confirmed in the editor.
/// Which bank an unknown sender is: one k has ([id]) or a new one.
class BankChoice {
  const BankChoice.existing(String this.id)
    : newName = null,
      emailSender = null;
  const BankChoice.create(String this.newName, {this.emailSender}) : id = null;

  final String? id;
  final String? newName;

  /// Optional alert mail address/domain for a new bank.
  final String? emailSender;
}

class ReviewDraft {
  const ReviewDraft({
    required this.marks,
    required this.direction,
    this.kind = TemplateKind.transaction,
    this.bank,
    this.dueDate,
    this.amountMinor,
    this.accountId,
    this.payee,
    this.ref,
    this.occurredAt,
    this.categoryId,
    this.learn = true,
  });

  final List<FieldMark> marks;
  final Direction direction;

  /// A payment, or an AutoPay alert ([TemplateKind.mandate], design 03i).
  final TemplateKind kind;

  /// Required when the sender is unknown.
  final BankChoice? bank;
  final DateTime? dueDate;

  /// Typed values; null → taken from the mark.
  final int? amountMinor;
  final String? accountId;
  final String? payee;
  final String? ref;
  final DateTime? occurredAt;
  final String? categoryId;
  final bool learn;

  bool get isMandate => kind == TemplateKind.mandate;
}

/// What to put back when the owner taps Undo (design 03k).
class ReviewUndo {
  const ReviewUndo({required this.rawIds, this.templateId, this.unblock});

  final List<String> rawIds;

  /// A "skip messages like this" format to forget.
  final String? templateId;

  /// A sender core to stop treating as "not a bank".
  final String? unblock;
}

class SaveResult {
  const SaveResult({required this.learned, this.learnError, this.cleared = 0});

  final bool learned;

  /// Why the format could not be learned (the payment is saved anyway).
  final String? learnError;

  /// Other waiting messages the new format read on its own.
  final int cleared;
}

/// Review queue: list, prefill, save (+ learn a format), dismiss.
class ReviewService {
  ReviewService(this._db, this._ingest, this._ledger, this._banks);

  final AppDatabase _db;
  final IngestionService _ingest;
  final LedgerRepository _ledger;
  final BankRepository _banks;

  Stream<List<ReviewItem>> watchQueue() =>
      (_db.select(_db.rawMessages)
            ..where(
              (r) =>
                  r.deletedAt.isNull() &
                  r.status.equalsValue(RawMessageStatus.needsReview),
            )
            ..orderBy([(r) => OrderingTerm.desc(r.receivedAt)]))
          .watch()
          .asyncMap((rows) async => [for (final r in rows) await item(r)]);

  Future<ReviewItem> item(RawMessage raw) async {
    var guess = await _ingest.parseRaw(raw);
    if (guess.status == ParseStatus.notBank) {
      guess =
          probeUnknown(_inputOf(raw)) ??
          const ParseResult(
            status: ParseStatus.needsReview,
            missing: ['sender'],
            note: unknownSenderNote,
          );
    }
    return ReviewItem(
      raw: raw,
      text: normalizeText([?raw.subject, raw.body].join(' ')),
      guess: guess,
    );
  }

  /// The draft's values as parser fields.
  ParsedFields fieldsOf(ReviewItem item, ReviewDraft d) {
    String? marked(MarkField f) {
      for (final m in d.marks) {
        if (m.field == f) return m.valueIn(item.text);
      }
      return null;
    }

    final date = marked(MarkField.date);
    final due = marked(MarkField.dueDate);
    final balance = marked(MarkField.balance);
    final payee = d.payee ?? marked(MarkField.payee);
    final amount = marked(MarkField.amount);
    return ParsedFields(
      amountMinor:
          d.amountMinor ?? (amount == null ? null : parseAmountMinor(amount)),
      direction: d.isMandate ? Direction.debit : d.direction,
      // Filed as an ATM withdrawal: it's cash in hand, like a parsed one.
      txnType: d.categoryId == atmCategoryId
          ? TxnType.atm
          : item.guess.fields.txnType ?? TxnType.other,
      last4: marked(MarkField.account),
      card: marked(MarkField.card),
      payee: payee == null ? null : cleanPayee(payee),
      ref: d.ref ?? marked(MarkField.ref),
      occurredAt:
          d.occurredAt ??
          resolveOccurredAt(
            date == null ? null : parseBankDate(date),
            item.raw.receivedAt,
          ),
      balanceMinor: balance == null ? null : parseAmountMinor(balance),
      dueDate: d.dueDate ?? (due == null ? null : parseBankDate(due)?.value),
    );
  }

  Future<SaveResult> save(ReviewItem start, ReviewDraft d) async {
    final fields = fieldsOf(start, d);
    if (fields.amountMinor == null) {
      throw ArgumentError('amount is required');
    }
    if (d.isMandate && fields.dueDate == null) {
      throw ArgumentError('due date is required');
    }

    // Unknown sender: the bank (new or not) and its sender rule come first,
    // so the format below is learned for that bank.
    var item = start;
    final namedBank = item.unknownSender;
    if (namedBank) {
      final choice = d.bank;
      if (choice == null) throw ArgumentError('pick the bank first');
      final bankId = choice.id ?? await _banks.addBank(choice.newName!);
      await _banks.addSender(bankId, Channel.sms, senderCore(item.raw.sender));
      final mail = choice.emailSender?.trim();
      if (mail != null && mail.isNotEmpty) {
        await _banks.addSender(bankId, Channel.email, mail);
      }
      await _ingest.assignBank(item.raw.sender, bankId);
      _ingest.invalidate();
      final raw = await (_db.select(
        _db.rawMessages,
      )..where((r) => r.id.equals(item.raw.id))).getSingle();
      item = await this.item(raw);
    }
    final bankId = item.bankId!;

    String? templateId;
    String? learnError;
    if (d.learn) {
      final (template, error) = _learn(item, d, fields);
      learnError = error;
      if (template != null) {
        await _db
            .into(_db.parserTemplates)
            .insert(
              ParserTemplatesCompanion.insert(
                id: Value(template.id),
                bankId: bankId,
                channel: item.raw.channel,
                kind: d.kind,
                name: 'Learned from ${item.raw.sender}',
                pattern: template.pattern,
                fieldDefaults: Value(jsonEncode(template.defaults)),
                priority: Value(template.priority),
                sampleRawMessageId: Value(item.raw.id),
              ),
            );
        templateId = template.id;
        _ingest.invalidate();
      }
    }

    await _ingest.logReviewed(
      item.raw,
      fields,
      kind: d.kind,
      accountId: d.isMandate ? null : d.accountId,
      categoryId: d.isMandate ? null : d.categoryId,
      templateId: templateId,
    );

    await _linkCard(item, d);

    // A category picked here is taught for the merchant too.
    if (d.categoryId != null && !d.isMandate) {
      final txnId = await _txnFor(item.raw.id);
      if (txnId != null) {
        await _ledger.setCategory(txnId, d.categoryId!, applyToMerchant: true);
      }
    }

    final cleared = templateId == null && !namedBank
        ? 0
        : await _ingest.reprocessReview();
    return SaveResult(
      learned: templateId != null,
      learnError: learnError,
      cleared: cleared,
    );
  }

  /// A learned format's sample, ready to re-mark (Message formats → Edit).
  Future<ReviewItem?> itemById(String rawId) async {
    final raw = await (_db.select(
      _db.rawMessages,
    )..where((r) => r.id.equals(rawId))).getSingleOrNull();
    return raw == null ? null : item(raw);
  }

  /// Replaces learned format [oldId] with one built from the new marks on
  /// its sample. Logs nothing (the sample's payment exists already). The
  /// old format is kept when the new one doesn't read the sample back.
  Future<SaveResult> relearn(
    String oldId,
    ReviewItem item,
    ReviewDraft d,
  ) async {
    final old = await (_db.select(
      _db.parserTemplates,
    )..where((t) => t.id.equals(oldId))).getSingle();
    final (template, error) = _learn(item, d, fieldsOf(item, d));
    if (template == null) return SaveResult(learned: false, learnError: error);
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db
          .into(_db.parserTemplates)
          .insert(
            ParserTemplatesCompanion.insert(
              id: Value(template.id),
              bankId: old.bankId,
              channel: old.channel,
              kind: d.kind,
              name: old.name,
              pattern: template.pattern,
              fieldDefaults: Value(jsonEncode(template.defaults)),
              priority: Value(template.priority),
              sampleRawMessageId: Value(item.raw.id),
              enabled: Value(old.enabled),
            ),
          );
      await (_db.update(
        _db.parserTemplates,
      )..where((t) => t.id.equals(oldId))).write(
        ParserTemplatesCompanion(updatedAt: Value(now), deletedAt: Value(now)),
      );
      // Messages it read count for the new one (uses stay).
      await (_db.update(_db.rawMessages)
            ..where((r) => r.templateId.equals(oldId)))
          .write(RawMessagesCompanion(templateId: Value(template.id)));
    });
    _ingest.invalidate();
    await _linkCard(item, d);
    return SaveResult(learned: true, cleared: await _ingest.reprocessReview());
  }

  /// A marked debit card joins the payment's account.
  Future<void> _linkCard(ReviewItem item, ReviewDraft d) async {
    final card = d.marks.where((m) => m.field == MarkField.card).firstOrNull;
    if (card != null && !d.isMandate) {
      final txnId = await _txnFor(item.raw.id);
      final txn = txnId == null
          ? null
          : await (_db.select(
              _db.transactions,
            )..where((t) => t.id.equals(txnId))).getSingleOrNull();
      final account = txn?.accountId == null
          ? null
          : await (_db.select(
              _db.accounts,
            )..where((a) => a.id.equals(txn!.accountId!))).getSingleOrNull();
      if (account != null &&
          (account.type == AccountType.savings ||
              account.type == AccountType.current)) {
        await _ledger.addDebitCard(account.id, card.valueIn(item.text));
      }
    }
  }

  /// Not a transaction (design 03j). With [skipSimilar], k also learns a
  /// format that skips messages shaped like this one, and clears the
  /// waiting ones it matches.
  Future<ReviewUndo> notATransaction(
    ReviewItem item, {
    bool skipSimilar = false,
  }) async {
    await _ingest.markNotTransaction(item.raw.id);
    if (!skipSimilar || item.bankId == null) {
      return ReviewUndo(rawIds: [item.raw.id]);
    }
    final pattern = skipPattern(item.text);
    final id = 'user_${newId()}';
    if (!_skips(item, id, pattern)) return ReviewUndo(rawIds: [item.raw.id]);
    await _db
        .into(_db.parserTemplates)
        .insert(
          ParserTemplatesCompanion.insert(
            id: Value(id),
            bankId: item.bankId!,
            channel: item.raw.channel,
            kind: TemplateKind.ignore,
            name: 'Skip, learned from ${item.raw.sender}',
            pattern: pattern,
            priority: const Value(50),
            sampleRawMessageId: Value(item.raw.id),
          ),
        );
    await (_db.update(_db.rawMessages)..where((r) => r.id.equals(item.raw.id)))
        .write(RawMessagesCompanion(templateId: Value(id)));
    _ingest.invalidate();
    final cleared = await _ingest.reprocessReviewIds();
    return ReviewUndo(rawIds: [item.raw.id, ...cleared], templateId: id);
  }

  /// "Not a bank": blocks the sender; its waiting messages leave Review.
  Future<ReviewUndo> notABank(ReviewItem item) async {
    final ids = await _ingest.markNotABank(item.raw.sender);
    return ReviewUndo(rawIds: ids, unblock: senderCore(item.raw.sender));
  }

  Future<void> undo(ReviewUndo u) async {
    if (u.templateId != null) {
      final now = DateTime.now();
      await (_db.update(
        _db.parserTemplates,
      )..where((t) => t.id.equals(u.templateId!))).write(
        ParserTemplatesCompanion(updatedAt: Value(now), deletedAt: Value(now)),
      );
    }
    if (u.unblock != null) await _ingest.blocked.remove(u.unblock!);
    _ingest.invalidate();
    await _ingest.restoreToReview(u.rawIds);
  }

  /// Proves a skip format reads its own sample as "not a transaction".
  bool _skips(ReviewItem item, String id, String pattern) {
    final check = ParserEngine(
      banks: const [],
      senderRules: [
        SenderRule(item.bankId!, item.raw.channel, senderKeyOf(item.raw)),
      ],
      userTemplates: [
        ParserTemplate(
          id: id,
          bankCode: item.bankId!,
          channel: item.raw.channel,
          kind: TemplateKind.ignore,
          name: 'skip',
          pattern: pattern,
          priority: 50,
        ),
      ],
    ).parse(_inputOf(item.raw));
    return check.status == ParseStatus.nonTransaction && check.templateId == id;
  }

  Future<String?> _txnFor(String rawId) async {
    final row = await (_db.select(
      _db.transactionSources,
    )..where((s) => s.rawMessageId.equals(rawId))).getSingleOrNull();
    return row?.transactionId;
  }

  /// Builds a format from the marks and proves it reads the sample back to
  /// the same values. Tries capturing the direction word first (one format
  /// for both debits and credits), then a fixed direction.
  (ParserTemplate?, String?) _learn(
    ReviewItem item,
    ReviewDraft d,
    ParsedFields want,
  ) {
    final bankId = item.bankId!;
    final values = <String, String>{
      for (final m in d.marks)
        // An AutoPay format reads the due date, not the message date.
        if (!(d.isMandate && m.field == MarkField.date) &&
            !(!d.isMandate && m.field == MarkField.dueDate))
          m.field.group: m.valueIn(item.text),
    };
    if (!values.containsKey(Fields.amount)) {
      return (null, 'mark the amount in the message to learn this format');
    }
    if (d.isMandate && !values.containsKey(Fields.dueDate)) {
      return (null, 'mark the due date in the message to learn this format');
    }
    String? lastError;
    // AutoPay alerts are always debits; no direction to capture.
    for (final captureDirection in d.isMandate ? [false] : [true, false]) {
      final v = {...values};
      if (!captureDirection) v.remove(Fields.direction);
      if (captureDirection && !v.containsKey(Fields.direction)) continue;
      final generated = TemplateGenerator().generate(
        id: 'user_${newId()}',
        bankCode: bankId,
        channel: item.raw.channel,
        sampleText: item.text,
        fieldValues: v,
        kind: d.kind,
        defaults: {
          if (!captureDirection && !d.isMandate) 'direction': d.direction.name,
          // Later messages of this shape are ATM withdrawals too.
          if (d.categoryId == atmCategoryId && !d.isMandate) 'txnType': 'atm',
        },
      );
      if (!generated.ok) {
        lastError = generated.error;
        continue;
      }
      final t = generated.template!;
      final check = ParserEngine(
        banks: const [],
        senderRules: [
          SenderRule(bankId, item.raw.channel, senderKeyOf(item.raw)),
        ],
        userTemplates: [t],
      ).parse(_inputOf(item.raw));
      final got = check.fields;
      final mismatch = check.status != ParseStatus.parsed
          ? 'the new format does not read this message (${check.note ?? check.status.name})'
          : got.amountMinor != want.amountMinor
          ? 'amount reads back differently'
          : got.direction != want.direction
          ? 'debit/credit reads back differently'
          : (want.last4 != null && got.last4 != want.last4)
          ? 'account reads back differently'
          : (d.isMandate && !_sameDay(got.dueDate, want.dueDate))
          ? 'due date reads back differently'
          : null;
      if (mismatch == null) return (t, null);
      lastError = mismatch;
    }
    return (null, lastError);
  }
}

bool _sameDay(DateTime? a, DateTime? b) =>
    a != null &&
    b != null &&
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day;

RawInput _inputOf(RawMessage raw) => RawInput(
  channel: raw.channel,
  sender: raw.sender,
  body: raw.body,
  subject: raw.subject,
  receivedAt: raw.receivedAt,
);

/// A skip format from one sample: the message's first 20 words in order,
/// any word with a digit (amounts, dates, account numbers) left free.
/// Anchored at the start, so only messages shaped like the sample match.
String skipPattern(String text) {
  final words = text.split(' ').where((w) => w.isNotEmpty).take(20);
  return '^${words.map((w) => w.contains(RegExp(r'\d')) ? r'\S+' : RegExp.escape(w)).join(r'\s+')}';
}

/// A sender rule that matches this exact sender, for verification only.
String senderKeyOf(RawMessage raw) {
  if (raw.channel == Channel.sms) return raw.sender;
  final m = RegExp(r'<([^>]+)>').firstMatch(raw.sender);
  return (m?.group(1) ?? raw.sender).trim().toLowerCase();
}
