import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../core/ids.dart';
import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import '../ingest/ingestion_service.dart';
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

  String get bankId => raw.bankId!;

  /// Short reason shown on the queue card.
  String get reason {
    if (guess.missing.contains('template')) return 'No format matched';
    if (guess.fields.amountMinor == null) return 'Amount missing';
    if (guess.fields.direction == null) return 'Debit or credit unclear';
    if (guess.fields.last4 == null) return 'Account missing';
    return 'Needs a look';
  }
}

/// What the owner confirmed in the editor.
class ReviewDraft {
  const ReviewDraft({
    required this.marks,
    required this.direction,
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

  /// Typed values; null → taken from the mark.
  final int? amountMinor;
  final String? accountId;
  final String? payee;
  final String? ref;
  final DateTime? occurredAt;
  final String? categoryId;
  final bool learn;
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
  ReviewService(this._db, this._ingest, this._ledger);

  final AppDatabase _db;
  final IngestionService _ingest;
  final LedgerRepository _ledger;

  Stream<List<ReviewItem>> watchQueue() =>
      (_db.select(_db.rawMessages)
            ..where(
              (r) =>
                  r.deletedAt.isNull() &
                  r.bankId.isNotNull() &
                  r.status.equalsValue(RawMessageStatus.needsReview),
            )
            ..orderBy([(r) => OrderingTerm.desc(r.receivedAt)]))
          .watch()
          .asyncMap((rows) async => [for (final r in rows) await item(r)]);

  Future<ReviewItem> item(RawMessage raw) async => ReviewItem(
    raw: raw,
    text: normalizeText([?raw.subject, raw.body].join(' ')),
    guess: await _ingest.parseRaw(raw),
  );

  /// The draft's values as parser fields.
  ParsedFields fieldsOf(ReviewItem item, ReviewDraft d) {
    String? marked(MarkField f) {
      for (final m in d.marks) {
        if (m.field == f) return m.valueIn(item.text);
      }
      return null;
    }

    final date = marked(MarkField.date);
    final balance = marked(MarkField.balance);
    final payee = d.payee ?? marked(MarkField.payee);
    final amount = marked(MarkField.amount);
    return ParsedFields(
      amountMinor:
          d.amountMinor ?? (amount == null ? null : parseAmountMinor(amount)),
      direction: d.direction,
      txnType: item.guess.fields.txnType ?? TxnType.other,
      last4: marked(MarkField.account),
      payee: payee == null ? null : cleanPayee(payee),
      ref: d.ref ?? marked(MarkField.ref),
      occurredAt:
          d.occurredAt ??
          resolveOccurredAt(
            date == null ? null : parseBankDate(date),
            item.raw.receivedAt,
          ),
      balanceMinor: balance == null ? null : parseAmountMinor(balance),
    );
  }

  Future<SaveResult> save(ReviewItem item, ReviewDraft d) async {
    final fields = fieldsOf(item, d);
    if (fields.amountMinor == null) {
      throw ArgumentError('amount is required');
    }

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
                bankId: item.bankId,
                channel: item.raw.channel,
                kind: TemplateKind.transaction,
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
      accountId: d.accountId,
      categoryId: d.categoryId,
      templateId: templateId,
    );

    // A category picked here is taught for the merchant too.
    if (d.categoryId != null) {
      final txnId = await _txnFor(item.raw.id);
      if (txnId != null) {
        await _ledger.setCategory(txnId, d.categoryId!, applyToMerchant: true);
      }
    }

    final cleared = templateId == null ? 0 : await _ingest.reprocessReview();
    return SaveResult(
      learned: templateId != null,
      learnError: learnError,
      cleared: cleared,
    );
  }

  Future<void> notATransaction(ReviewItem item) =>
      _ingest.markNotTransaction(item.raw.id);

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
    final values = <String, String>{
      for (final m in d.marks) m.field.group: m.valueIn(item.text),
    };
    if (!values.containsKey(Fields.amount)) {
      return (null, 'mark the amount in the message to learn this format');
    }
    String? lastError;
    for (final captureDirection in [true, false]) {
      final v = {...values};
      if (!captureDirection) v.remove(Fields.direction);
      if (captureDirection && !v.containsKey(Fields.direction)) continue;
      final generated = TemplateGenerator().generate(
        id: 'user_${newId()}',
        bankCode: item.bankId,
        channel: item.raw.channel,
        sampleText: item.text,
        fieldValues: v,
        defaults: captureDirection ? const {} : {'direction': d.direction.name},
      );
      if (!generated.ok) {
        lastError = generated.error;
        continue;
      }
      final t = generated.template!;
      final check =
          ParserEngine(
            banks: const [],
            senderRules: [
              SenderRule(item.bankId, item.raw.channel, _senderKey(item.raw)),
            ],
            userTemplates: [t],
          ).parse(
            RawInput(
              channel: item.raw.channel,
              sender: item.raw.sender,
              body: item.raw.body,
              subject: item.raw.subject,
              receivedAt: item.raw.receivedAt,
            ),
          );
      final got = check.fields;
      final mismatch = check.status != ParseStatus.parsed
          ? 'the new format does not read this message (${check.note ?? check.status.name})'
          : got.amountMinor != want.amountMinor
          ? 'amount reads back differently'
          : got.direction != want.direction
          ? 'debit/credit reads back differently'
          : (want.last4 != null && got.last4 != want.last4)
          ? 'account reads back differently'
          : null;
      if (mismatch == null) return (t, null);
      lastError = mismatch;
    }
    return (null, lastError);
  }

  /// A sender rule that matches this exact sender, for verification only.
  String _senderKey(RawMessage raw) {
    if (raw.channel == Channel.sms) return raw.sender;
    final m = RegExp(r'<([^>]+)>').firstMatch(raw.sender);
    return (m?.group(1) ?? raw.sender).trim().toLowerCase();
  }
}
