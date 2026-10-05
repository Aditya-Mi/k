import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import 'category_resolver.dart';
import 'transfer_linker.dart';

/// A bank message as it enters the app, from any channel.
class IncomingMessage {
  const IncomingMessage({
    required this.channel,
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.subject,
    this.externalId,
    this.simSlot,
    this.emailAccountId,
  });

  final Channel channel;
  final String sender;
  final String body;
  final String? subject;
  final DateTime receivedAt;
  final String? externalId;
  final int? simSlot;
  final String? emailAccountId;

  /// sha256(channel|sender|receivedAt|body): same message twice → same hash.
  String get contentHash => sha256
      .convert(
        utf8.encode(
          '${channel.name}|$sender|${receivedAt.millisecondsSinceEpoch}|'
          '${subject ?? ''}|$body',
        ),
      )
      .toString();
}

enum IngestOutcome {
  /// Already stored (same hash, or same text from same sender minutes apart).
  duplicate,

  /// Not a configured bank sender — dropped, nothing stored.
  notBank,

  /// Stored and logged as a transaction.
  transaction,

  /// Same payment already logged from the other channel (SMS ↔ email):
  /// this message became a second source of that transaction.
  merged,

  /// AutoPay / e-mandate alert stored as an upcoming charge.
  upcoming,

  /// Bank message the parser could not fully read → review queue.
  needsReview,

  /// OTP, promo, declined… stored for the trail, not logged.
  nonTransaction,
}

/// raw_messages → ParserEngine → account / merchant / category → transaction.
/// Idempotent: re-ingesting a message is a no-op.
class IngestionService {
  IngestionService(this._db) : _transfers = TransferLinker(_db);

  final AppDatabase _db;
  final TransferLinker _transfers;
  ParserEngine? _engine;
  CategoryResolver? _categories;

  /// Same SMS read twice (live + inbox) may carry slightly different times on
  /// some OEMs; identical text from the same sender this close is one message.
  static const duplicateWindow = Duration(minutes: 5);

  /// Call after sender rules, templates or category rules change.
  void invalidate() {
    _engine = null;
    _categories = null;
  }

  Future<ParserEngine> _parser() async => _engine ??= await _buildEngine();

  Future<ParserEngine> _buildEngine() async {
    final senders = await (_db.select(
      _db.senderRules,
    )..where((r) => r.enabled.equals(true) & r.deletedAt.isNull())).get();
    final templates = await (_db.select(
      _db.parserTemplates,
    )..where((t) => t.enabled.equals(true) & t.deletedAt.isNull())).get();
    return ParserEngine(
      banks: builtInBanks,
      senderRules: [
        for (final s in senders) SenderRule(s.bankId, s.channel, s.pattern),
      ],
      userTemplates: [
        for (final t in templates)
          ParserTemplate(
            id: t.id,
            bankCode: t.bankId,
            channel: t.channel,
            kind: t.kind,
            name: t.name,
            pattern: t.pattern,
            defaults: (jsonDecode(t.fieldDefaults) as Map).map(
              (k, v) => MapEntry(k as String, v.toString()),
            ),
            priority: t.priority,
          ),
      ],
    );
  }

  Future<IngestOutcome> ingest(IncomingMessage m) async {
    final engine = await _parser();

    final result = engine.parse(
      RawInput(
        channel: m.channel,
        sender: m.sender,
        body: m.body,
        subject: m.subject,
        receivedAt: m.receivedAt,
      ),
    );
    if (result.status == ParseStatus.notBank) return IngestOutcome.notBank;

    return _db.transaction(() async {
      if (await _isDuplicate(m)) return IngestOutcome.duplicate;

      final noMoney = _emailWithoutAmount(m.channel, result);
      var status = switch (result.status) {
        ParseStatus.parsed => RawMessageStatus.parsed,
        ParseStatus.nonTransaction => RawMessageStatus.nonTransaction,
        _ when noMoney => RawMessageStatus.nonTransaction,
        _ => RawMessageStatus.needsReview,
      };
      final fields = result.fields;
      final isMandate = result.kind == TemplateKind.mandate;
      if (status == RawMessageStatus.parsed &&
          isMandate &&
          (fields.dueDate == null || fields.amountMinor == null)) {
        status = RawMessageStatus.needsReview;
      }

      final raw = await _db
          .into(_db.rawMessages)
          .insertReturning(
            RawMessagesCompanion.insert(
              channel: m.channel,
              bankId: Value(result.bankCode),
              sender: m.sender,
              subject: Value(m.subject),
              body: m.body,
              receivedAt: m.receivedAt,
              externalId: Value(m.externalId),
              emailAccountId: Value(m.emailAccountId),
              simSlot: Value(m.simSlot),
              contentHash: m.contentHash,
              status: status,
              templateId: Value(result.templateId),
              parseNote: Value(noMoney ? _noAmountNote : _note(result)),
            ),
          );

      if (status != RawMessageStatus.parsed) {
        return status == RawMessageStatus.nonTransaction
            ? IngestOutcome.nonTransaction
            : IngestOutcome.needsReview;
      }

      return _log(
        raw,
        result.bankCode!,
        result.kind,
        fields,
        normalizeText([?m.subject, m.body].join(' ')),
      );
    });
  }

  /// Parses a stored message with the current formats (review prefill,
  /// re-checks after learning).
  Future<ParseResult> parseRaw(RawMessage raw) async => (await _parser()).parse(
    RawInput(
      channel: raw.channel,
      sender: raw.sender,
      body: raw.body,
      subject: raw.subject,
      receivedAt: raw.receivedAt,
    ),
  );

  /// Logs a review-queue message from fields the owner confirmed.
  Future<void> logReviewed(
    RawMessage raw,
    ParsedFields fields, {
    String? accountId,
    String? categoryId,
    String? templateId,
  }) => _db.transaction(() async {
    await _log(
      raw,
      raw.bankId!,
      TemplateKind.transaction,
      fields,
      normalizeText([?raw.subject, raw.body].join(' ')),
      accountId: accountId,
      categoryId: categoryId,
    );
    await _markParsed(raw.id, templateId);
  });

  /// Re-reads every review-queue message; logs the ones that now parse.
  /// Returns how many left the queue.
  Future<int> reprocessReview() async {
    final waiting =
        await (_db.select(_db.rawMessages)..where(
              (r) =>
                  r.deletedAt.isNull() &
                  r.status.equalsValue(RawMessageStatus.needsReview),
            ))
            .get();
    var cleared = 0;
    for (final raw in waiting) {
      final result = await parseRaw(raw);
      if (_emailWithoutAmount(raw.channel, result)) {
        await _setNonTransaction(raw.id, _noAmountNote);
        cleared++;
        continue;
      }
      if (result.status != ParseStatus.parsed) continue;
      final f = result.fields;
      if (result.kind == TemplateKind.mandate &&
          (f.dueDate == null || f.amountMinor == null)) {
        continue;
      }
      await _db.transaction(() async {
        await _log(
          raw,
          result.bankCode!,
          result.kind,
          f,
          normalizeText([?raw.subject, raw.body].join(' ')),
        );
        await _markParsed(raw.id, result.templateId);
      });
      cleared++;
    }
    return cleared;
  }

  /// A payment no bank message reported (design 09), logged as added by the
  /// owner. On a tracked account, a late SMS/email for the same amount and
  /// direction within ±3 days becomes this row (see [_ownerAddedRow]).
  Future<String> addManual({
    required Direction direction,
    required int amountMinor,
    required DateTime occurredAt,
    String? accountId,
    String? payee,
    String? categoryId,
    String? note,
  }) => _db.transaction(() async {
    final categories = _categories ??= await CategoryResolver.load(_db);
    final name = payee?.trim();
    final merchant = await _merchantFor(name);
    final txn = await _db
        .into(_db.transactions)
        .insertReturning(
          TransactionsCompanion.insert(
            accountId: Value(accountId),
            amountMinor: amountMinor,
            direction: direction,
            txnType: TxnType.other,
            merchantId: Value(merchant?.id),
            payeeRaw: Value(name == null || name.isEmpty ? null : name),
            occurredAt: occurredAt,
            categoryId: Value(
              categoryId ??
                  categories.resolve(
                    merchantKey: merchant?.normalizedKey,
                    payee: name,
                  ),
            ),
            userEdited: Value(categoryId != null),
            notes: Value(note == null || note.trim().isEmpty ? null : note),
            origin: const Value(TxnOrigin.user),
          ),
        );
    if (accountId != null) await _transfers.autoLink(txn.id);
    return txn.id;
  });

  Future<void> markNotTransaction(String rawId) =>
      _setNonTransaction(rawId, 'marked not a transaction');

  Future<void> _setNonTransaction(String rawId, String note) =>
      (_db.update(_db.rawMessages)..where((r) => r.id.equals(rawId))).write(
        RawMessagesCompanion(
          status: const Value(RawMessageStatus.nonTransaction),
          parseNote: Value(note),
          updatedAt: Value(DateTime.now()),
        ),
      );

  static const _noAmountNote = 'email without an amount';

  /// Bank mail no format reads and with no amount anywhere in it (e-statements,
  /// notices) never reaches Review. SMS still does: a short SMS with no amount
  /// can be a format worth learning.
  static bool _emailWithoutAmount(Channel channel, ParseResult r) =>
      channel == Channel.email &&
      r.status == ParseStatus.needsReview &&
      r.fields.amountMinor == null;

  Future<void> _markParsed(String rawId, String? templateId) =>
      (_db.update(_db.rawMessages)..where((r) => r.id.equals(rawId))).write(
        RawMessagesCompanion(
          status: const Value(RawMessageStatus.parsed),
          templateId: Value(templateId),
          parseNote: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Parsed fields → upcoming charge or transaction (+ source link). Runs
  /// inside the caller's DB transaction.
  Future<IngestOutcome> _log(
    RawMessage raw,
    String bankId,
    TemplateKind kind,
    ParsedFields fields,
    String text, {
    String? accountId,
    String? categoryId,
  }) async {
    final categories = _categories ??= await CategoryResolver.load(_db);
    final isMandate = kind == TemplateKind.mandate;
    final merchant = await _merchantFor(fields.payee);
    if (isMandate) {
      await _db
          .into(_db.upcomingCharges)
          .insert(
            UpcomingChargesCompanion.insert(
              merchantId: Value(merchant?.id),
              amountMinor: fields.amountMinor!,
              currency: Value(fields.currency),
              dueDate: fields.dueDate!,
              mandateRef: Value(fields.mandateRef),
              rawMessageId: Value(raw.id),
              status: UpcomingChargeStatus.pending,
            ),
          );
      return IngestOutcome.upcoming;
    }

    final account = accountId != null
        ? await (_db.select(
            _db.accounts,
          )..where((a) => a.id.equals(accountId))).getSingle()
        : await _accountFor(bankId, fields, text);
    final occurredAt = fields.occurredAt ?? raw.receivedAt;

    // The same payment from the other channel (SMS ↔ email): one row, two
    // sources. The earlier copy keeps its fields; gaps are filled in.
    final twin = await _crossChannelTwin(
      raw.channel,
      account.id,
      fields,
      occurredAt,
    );
    if (twin != null) {
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(twin.id))).write(
        TransactionsCompanion(
          refNo: twin.refNo == null && fields.ref != null
              ? Value(fields.ref)
              : const Value.absent(),
          balanceMinor: twin.balanceMinor == null && fields.balanceMinor != null
              ? Value(fields.balanceMinor)
              : const Value.absent(),
          merchantId: twin.merchantId == null && merchant != null
              ? Value(merchant.id)
              : const Value.absent(),
          payeeRaw: twin.payeeRaw == null && fields.payee != null
              ? Value(fields.payee)
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _db
          .into(_db.transactionSources)
          .insert(
            TransactionSourcesCompanion.insert(
              transactionId: twin.id,
              rawMessageId: raw.id,
            ),
          );
      return IngestOutcome.merged;
    }

    // A late bank message for a side the owner added: it becomes that row.
    final added = await _ownerAddedRow(account.id, fields, occurredAt);
    if (added != null) {
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(added.id))).write(
        TransactionsCompanion(
          origin: const Value(TxnOrigin.message),
          occurredAt: Value(occurredAt),
          txnType: Value(fields.txnType ?? added.txnType),
          // The payee the owner typed beats the bank's (e.g. "RAZORPAY").
          merchantId: Value(added.merchantId ?? merchant?.id),
          payeeRaw: Value(added.payeeRaw ?? fields.payee),
          refNo: Value(fields.ref),
          balanceMinor: Value(fields.balanceMinor),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _db
          .into(_db.transactionSources)
          .insert(
            TransactionSourcesCompanion.insert(
              transactionId: added.id,
              rawMessageId: raw.id,
            ),
          );
      return IngestOutcome.transaction;
    }

    final txn = await _db
        .into(_db.transactions)
        .insertReturning(
          TransactionsCompanion.insert(
            accountId: Value(account.id),
            amountMinor: fields.amountMinor!,
            currency: Value(fields.currency),
            direction: fields.direction!,
            txnType: fields.txnType ?? TxnType.other,
            merchantId: Value(merchant?.id),
            payeeRaw: Value(fields.payee),
            refNo: Value(fields.ref),
            occurredAt: occurredAt,
            balanceMinor: Value(fields.balanceMinor),
            categoryId: Value(
              categoryId ??
                  categories.resolve(
                    merchantKey: merchant?.normalizedKey,
                    payee: fields.payee,
                    txnType: fields.txnType,
                  ),
            ),
            userEdited: Value(categoryId != null),
          ),
        );
    await _db
        .into(_db.transactionSources)
        .insert(
          TransactionSourcesCompanion.insert(
            transactionId: txn.id,
            rawMessageId: raw.id,
          ),
        );
    await _transfers.autoLink(txn.id);
    return IngestOutcome.transaction;
  }

  /// Cross-channel duplicate window (setting `dedup.windowMinutes`).
  Future<Duration> _dedupWindow() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((s) => s.key.equals('dedup.windowMinutes'))).getSingleOrNull();
    return Duration(minutes: int.tryParse(row?.value ?? '') ?? 10);
  }

  /// A row on the same account, amount and direction within the window that
  /// came only from the other channel. Same-channel repeats are separate
  /// payments (two ₹100 UPIs a minute apart are real).
  Future<Transaction?> _crossChannelTwin(
    Channel channel,
    String accountId,
    ParsedFields f,
    DateTime at,
  ) async {
    final window = await _dedupWindow();
    final t = _db.transactions;
    final src = _db.transactionSources;
    final raw = _db.rawMessages;
    final rows =
        await (_db.select(t).join([
              innerJoin(src, src.transactionId.equalsExp(t.id)),
              innerJoin(raw, raw.id.equalsExp(src.rawMessageId)),
            ])..where(
              t.deletedAt.isNull() &
                  t.accountId.equals(accountId) &
                  t.amountMinor.equals(f.amountMinor!) &
                  t.direction.equalsValue(f.direction!) &
                  t.occurredAt.isBetweenValues(
                    at.subtract(window),
                    at.add(window),
                  ),
            ))
            .get();
    final channels = <String, Set<Channel>>{};
    final byId = <String, Transaction>{};
    for (final r in rows) {
      final txn = r.readTable(t);
      byId[txn.id] = txn;
      (channels[txn.id] ??= {}).add(r.readTable(raw).channel);
    }
    Transaction? best;
    for (final MapEntry(key: id, value: seen) in channels.entries) {
      if (seen.contains(channel)) continue;
      final c = byId[id]!;
      if (best == null ||
          c.occurredAt.difference(at).abs() <
              best.occurredAt.difference(at).abs()) {
        best = c;
      }
    }
    return best;
  }

  /// Same account, amount and direction, added by the owner within ±3 days.
  Future<Transaction?> _ownerAddedRow(
    String accountId,
    ParsedFields f,
    DateTime at,
  ) async {
    const span = Duration(days: 3);
    final rows =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.origin.equalsValue(TxnOrigin.user) &
                  t.accountId.equals(accountId) &
                  t.amountMinor.equals(f.amountMinor!) &
                  t.direction.equalsValue(f.direction) &
                  t.occurredAt.isBetweenValues(at.subtract(span), at.add(span)),
            ))
            .get();
    if (rows.isEmpty) return null;
    rows.sort(
      (a, b) => a.occurredAt
          .difference(at)
          .abs()
          .compareTo(b.occurredAt.difference(at).abs()),
    );
    return rows.first;
  }

  Future<bool> _isDuplicate(IncomingMessage m) async {
    final byHash =
        await (_db.selectOnly(_db.rawMessages)
              ..addColumns([_db.rawMessages.id])
              ..where(_db.rawMessages.contentHash.equals(m.contentHash))
              ..limit(1))
            .getSingleOrNull();
    if (byHash != null) return true;

    final near =
        await (_db.selectOnly(_db.rawMessages)
              ..addColumns([_db.rawMessages.id])
              ..where(
                _db.rawMessages.channel.equalsValue(m.channel) &
                    _db.rawMessages.sender.equals(m.sender) &
                    _db.rawMessages.body.equals(m.body) &
                    _db.rawMessages.receivedAt.isBetweenValues(
                      m.receivedAt.subtract(duplicateWindow),
                      m.receivedAt.add(duplicateWindow),
                    ),
              )
              ..limit(1))
            .getSingleOrNull();
    return near != null;
  }

  String? _note(ParseResult r) {
    if (r.status == ParseStatus.parsed) return null;
    final missing = r.missing.isEmpty
        ? ''
        : ' (missing ${r.missing.join(', ')})';
    return '${r.note ?? r.status.name}$missing';
  }

  /// (bank, last4) → account, created on first sight.
  Future<Account> _accountFor(
    String bankId,
    ParsedFields f,
    String text,
  ) async {
    final last4 = f.last4;
    final type = inferAccountType(f.txnType, text);
    // Some alerts name no account ("Your account is credited"), and a debit
    // card spends from its savings account. If the bank has exactly one
    // savings/current account, it is that one.
    final soleSavings = last4 == null || type == AccountType.debitCard
        ? await _soleSavings(bankId)
        : null;
    if (last4 == null && soleSavings != null) return soleSavings;

    final existing =
        await (_db.select(_db.accounts)
              ..where(
                (a) =>
                    a.bankId.equals(bankId) &
                    a.deletedAt.isNull() &
                    (last4 == null ? a.last4.isNull() : a.last4.equals(last4)),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return _resolveMerged(existing);

    final created = await _db
        .into(_db.accounts)
        .insertReturning(
          AccountsCompanion.insert(
            bankId: bankId,
            type: type,
            last4: Value(last4),
            autoCreated: const Value(true),
            // Remember the card's digits, but log to the savings account.
            mergedIntoId: Value(
              type == AccountType.debitCard ? soleSavings?.id : null,
            ),
          ),
        );
    return _resolveMerged(created);
  }

  Future<Account?> _soleSavings(String bankId) async {
    final rows =
        await (_db.select(_db.accounts)..where(
              (a) =>
                  a.bankId.equals(bankId) &
                  a.deletedAt.isNull() &
                  a.mergedIntoId.isNull() &
                  a.last4.isNotNull() &
                  a.type.isInValues([AccountType.savings, AccountType.current]),
            ))
            .get();
    return rows.length == 1 ? rows.single : null;
  }

  /// Follows "merged into" links to the account that is shown.
  Future<Account> _resolveMerged(Account a) async {
    var current = a;
    for (var hops = 0; current.mergedIntoId != null && hops < 5; hops++) {
      final next = await (_db.select(
        _db.accounts,
      )..where((o) => o.id.equals(current.mergedIntoId!))).getSingleOrNull();
      if (next == null) break;
      current = next;
    }
    return current;
  }

  /// Payee → merchant via alias, then normalized key; created on first sight.
  Future<Merchant?> _merchantFor(String? payee) async {
    if (payee == null || payee.trim().isEmpty) return null;
    final alias = payee.trim().toLowerCase();
    final key = merchantKey(payee);
    if (key.isEmpty) return null;

    final viaAlias =
        await (_db.select(_db.merchants).join([
                innerJoin(
                  _db.merchantAliases,
                  _db.merchantAliases.merchantId.equalsExp(_db.merchants.id),
                ),
              ])
              ..where(_db.merchantAliases.alias.equals(alias))
              ..limit(1))
            .map((r) => r.readTable(_db.merchants))
            .getSingleOrNull();
    if (viaAlias != null) return _followMerged(viaAlias);

    final merchant =
        await (_db.select(
          _db.merchants,
        )..where((mm) => mm.normalizedKey.equals(key))).getSingleOrNull() ??
        await _db
            .into(_db.merchants)
            .insertReturning(
              MerchantsCompanion.insert(
                normalizedKey: key,
                displayName: merchantDisplayName(payee, key),
              ),
            );
    final target = await _followMerged(merchant);
    await _db
        .into(_db.merchantAliases)
        .insert(
          MerchantAliasesCompanion.insert(alias: alias, merchantId: target.id),
          mode: InsertMode.insertOrIgnore,
        );
    return target;
  }

  /// A renamed-together merchant points at the one that kept its row.
  Future<Merchant> _followMerged(Merchant m) async {
    var current = m;
    for (var hops = 0; current.mergedIntoId != null && hops < 5; hops++) {
      final next = await (_db.select(
        _db.merchants,
      )..where((o) => o.id.equals(current.mergedIntoId!))).getSingleOrNull();
      if (next == null) break;
      current = next;
    }
    return current;
  }
}

/// Card alerts rarely say which kind; a limit means credit card.
AccountType inferAccountType(TxnType? type, String text) {
  final t = text.toLowerCase();
  if (t.contains('credit card') ||
      t.contains('avl limit') ||
      t.contains('avl lmt') ||
      t.contains('available limit')) {
    return AccountType.creditCard;
  }
  if (t.contains('debit card')) return AccountType.debitCard;
  if (type == TxnType.card) return AccountType.creditCard;
  return AccountType.savings;
}

final _vowel = RegExp('[aeiouy]', caseSensitive: false);

/// "ZEPTO MARKETPLACE PR" → "Zepto Marketplace PR"; "swiggy.upi@axb" →
/// "Swiggy"; mixed-case names are kept. Vowel-poor words read as acronyms
/// and stay capitals (IRCTC, DMRC, KFC).
String merchantDisplayName(String payee, String key) {
  final source = payee.contains('@') ? key : payee.trim();
  if (!payee.contains('@') && source != source.toUpperCase()) return source;
  return source
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) {
        final letters = w.replaceAll(RegExp('[^A-Za-z]'), '').length;
        final vowels = _vowel.allMatches(w).length;
        if (letters > 1 && vowels / letters < 0.25) return w.toUpperCase();
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      })
      .join(' ');
}
