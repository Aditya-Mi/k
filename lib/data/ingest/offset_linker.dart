import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../core/ids.dart';
import '../db/app_database.dart' hide ParserTemplate, SenderRule;

/// Groups payments that cancel out (see [Transactions.offsetId]): the owner
/// links them by hand ("Cancels out with…"), and k links a failed payment's
/// reversal on its own.
///
/// Auto rule: a credit on the same account, same amount and currency, up to
/// [reversalWindow] after a debit, that either carries the debit's reference
/// or reads like a reversal ("reversed", "failed", "credited back"…).
/// Merchant refunds are left alone: they lower spent in the month they
/// arrive, through their category. Rows the owner unlinked
/// ([Transactions.autoOffsetOff]) are never auto-linked again.
class OffsetLinker {
  OffsetLinker(this._db);

  final AppDatabase _db;

  static const reversalWindow = Duration(days: 7);

  static final _reversalWords = RegExp(
    r'\b(revers(al|ed|e)|reverted|failed|unsuccessful|credited back|'
    r'auto[- ]?refund(ed)?)\b',
    caseSensitive: false,
  );

  /// Links [txnId] (a credit) to the debit it reverses. [text] is the
  /// message it came from; read from its sources when empty. True if linked.
  Future<bool> autoReversal(String txnId, {String text = ''}) async {
    final t = await _byId(txnId);
    if (t == null || !_eligible(t) || t.direction != Direction.credit) {
      return false;
    }
    if (text.isEmpty) text = await _messageText(t.id);
    final debit = await _reversedDebit(t, text);
    if (debit == null) return false;
    await link(debit.id, t.id, auto: true);
    return true;
  }

  /// Backfill over recent credits. Returns links made.
  Future<int> autoReversalsAll({Duration back = const Duration(days: 120)}) =>
      _db.transaction(() async {
        final credits =
            await (_db.select(_db.transactions)..where(
                  (t) =>
                      t.deletedAt.isNull() &
                      t.offsetId.isNull() &
                      t.transferId.isNull() &
                      t.autoOffsetOff.equals(false) &
                      t.accountId.isNotNull() &
                      t.direction.equalsValue(Direction.credit) &
                      t.occurredAt.isBiggerOrEqualValue(
                        DateTime.now().subtract(back),
                      ),
                ))
                .get();
        var n = 0;
        for (final c in credits) {
          if (await autoReversal(c.id)) n++;
        }
        return n;
      });

  /// Puts [aId] and [bId] in one group. Either may already be in one: the
  /// groups join.
  Future<void> link(String aId, String bId, {bool auto = false}) =>
      _db.transaction(() async {
        final a = await _byId(aId), b = await _byId(bId);
        if (a == null || b == null || a.id == b.id) return;
        if (a.transferId != null || b.transferId != null) return;
        final id = a.offsetId ?? b.offsetId ?? newId();
        final now = DateTime.now();
        final other = b.offsetId != null && b.offsetId != id
            ? b.offsetId
            : a.offsetId != null && a.offsetId != id
            ? a.offsetId
            : null;
        await (_db.update(_db.transactions)..where(
              (t) =>
                  t.id.isIn([a.id, b.id]) |
                  (other == null
                      ? const Constant(false)
                      : t.offsetId.equals(other)),
            ))
            .write(
              TransactionsCompanion(
                offsetId: Value(id),
                autoOffsetOff: const Value(false),
                updatedAt: Value(now),
              ),
            );
      });

  /// "Doesn't cancel out": takes [txnId] out of its group (a group left
  /// with one payment ends). Unlinked rows aren't auto-linked again.
  Future<void> unlink(String txnId) => _db.transaction(() async {
    final t = await _byId(txnId);
    final group = t?.offsetId;
    if (t == null || group == null) return;
    final now = DateTime.now();
    final rest =
        await (_db.select(_db.transactions)..where(
              (o) =>
                  o.offsetId.equals(group) &
                  o.id.equals(t.id).not() &
                  o.deletedAt.isNull(),
            ))
            .get();
    await (_db.update(_db.transactions)..where(
          (o) =>
              o.id.equals(t.id) |
              (rest.length < 2
                  ? o.offsetId.equals(group)
                  : const Constant(false)),
        ))
        .write(
          TransactionsCompanion(
            offsetId: const Value(null),
            autoOffsetOff: const Value(true),
            updatedAt: Value(now),
          ),
        );
  });

  /// "No" to a suggested pair: neither is suggested or auto-linked again.
  Future<void> dismiss(Iterable<String> ids) =>
      (_db.update(_db.transactions)..where((t) => t.id.isIn(ids))).write(
        TransactionsCompanion(
          autoOffsetOff: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<Transaction?> _reversedDebit(Transaction t, String text) async {
    final debits =
        await (_db.select(_db.transactions)
              ..where(
                (o) =>
                    o.deletedAt.isNull() &
                    o.offsetId.isNull() &
                    o.transferId.isNull() &
                    o.emiId.isNull() &
                    o.autoOffsetOff.equals(false) &
                    o.accountId.equals(t.accountId!) &
                    o.amountMinor.equals(t.amountMinor) &
                    o.currency.equals(t.currency) &
                    o.direction.equalsValue(Direction.debit) &
                    o.occurredAt.isBetweenValues(
                      t.occurredAt.subtract(reversalWindow),
                      t.occurredAt,
                    ),
              )
              ..orderBy([(o) => OrderingTerm.desc(o.occurredAt)]))
            .get();
    if (debits.isEmpty) return null;
    bool sameRef(Transaction d) {
      final ref = d.refNo;
      if (ref == null || ref.length < 6) return false;
      return ref == t.refNo || text.contains(ref);
    }

    final byRef = debits.where(sameRef).firstOrNull;
    if (byRef != null) return byRef;
    return _reversalWords.hasMatch(text) ? debits.first : null;
  }

  Future<String> _messageText(String txnId) async {
    final rows = await (_db.select(_db.rawMessages).join([
      innerJoin(
        _db.transactionSources,
        _db.transactionSources.rawMessageId.equalsExp(_db.rawMessages.id),
      ),
    ])..where(_db.transactionSources.transactionId.equals(txnId))).get();
    return [
      for (final r in rows) ...[
        ?r.readTable(_db.rawMessages).subject,
        r.readTable(_db.rawMessages).body,
      ],
    ].join(' ');
  }

  bool _eligible(Transaction t) =>
      t.deletedAt == null &&
      t.offsetId == null &&
      t.transferId == null &&
      t.emiId == null &&
      !t.autoOffsetOff &&
      t.accountId != null;

  Future<Transaction?> _byId(String id) => (_db.select(
    _db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
}
