import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../core/ids.dart';
import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import 'category_resolver.dart';

const transfersCategoryId = 'cat_transfers';

/// Links money moved between the owner's own accounts so it counts as
/// neither spent nor came in.
///
/// Auto rule: a debit and a credit of the same amount and currency, on two
/// different own accounts, within [window]. Closest in time wins. Rows the
/// user unlinked ([Transactions.autoTransferOff]) are never auto-linked again.
class TransferLinker {
  TransferLinker(this._db);

  final AppDatabase _db;

  static const window = Duration(minutes: 30);

  /// Finds a partner for one transaction. Returns true if linked.
  Future<bool> autoLink(String txnId) async {
    final t = await _byId(txnId);
    if (t == null || !_eligible(t)) return false;
    final partner = await _bestPartner(t);
    if (partner == null) return false;
    await _link([t, partner]);
    return true;
  }

  /// Backfill: pairs every eligible unlinked transaction. Returns pairs made.
  Future<int> autoLinkAll() => _db.transaction(() async {
    final rows =
        await (_db.select(_db.transactions)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.transferId.isNull() &
                    t.autoTransferOff.equals(false) &
                    t.accountId.isNotNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
            .get();
    final used = <String>{};
    var pairs = 0;
    for (final debit in rows.where((r) => r.direction == Direction.debit)) {
      Transaction? best;
      for (final credit in rows) {
        if (used.contains(credit.id) || !_matches(debit, credit)) continue;
        if (best == null || _gap(debit, credit) < _gap(debit, best)) {
          best = credit;
        }
      }
      if (best == null) continue;
      used
        ..add(debit.id)
        ..add(best.id);
      await _link([debit, best]);
      pairs++;
    }
    return pairs;
  });

  /// Same-amount, opposite-direction rows on other accounts within ±3 days —
  /// what "Mark as self transfer" offers as the other side.
  Future<List<Transaction>> candidatesFor(String txnId) async {
    final t = await _byId(txnId);
    if (t == null) return const [];
    const span = Duration(days: 3);
    final rows =
        await (_db.select(_db.transactions)..where(
              (o) =>
                  o.deletedAt.isNull() &
                  o.transferId.isNull() &
                  o.id.equals(t.id).not() &
                  o.amountMinor.equals(t.amountMinor) &
                  o.currency.equals(t.currency) &
                  o.direction.equalsValue(_opposite(t.direction)) &
                  o.occurredAt.isBetweenValues(
                    t.occurredAt.subtract(span),
                    t.occurredAt.add(span),
                  ),
            ))
            .get();
    return rows.where((o) => o.accountId != t.accountId).toList()
      ..sort((a, b) => _gap(t, a).compareTo(_gap(t, b)));
  }

  /// User marks a self transfer, with the other side if it is tracked.
  ///
  /// [addOnAccountId]: the other side is an account in k whose bank sent no
  /// message — add the missing side there, marked as added by the owner.
  Future<void> markManual(
    String txnId, {
    String? partnerId,
    String? addOnAccountId,
  }) => _db.transaction(() async {
    final t = await _byId(txnId);
    if (t == null) return;
    var partner = partnerId == null ? null : await _byId(partnerId);
    if (partner == null && addOnAccountId != null) {
      partner = await _db
          .into(_db.transactions)
          .insertReturning(
            TransactionsCompanion.insert(
              accountId: Value(addOnAccountId),
              amountMinor: t.amountMinor,
              currency: Value(t.currency),
              direction: _opposite(t.direction),
              txnType: t.txnType,
              occurredAt: t.occurredAt,
              categoryId: const Value(transfersCategoryId),
              origin: const Value(TxnOrigin.user),
            ),
          );
    }
    await _link([t, ?partner]);
  });

  /// "Not a self transfer": unlinks both sides and stops auto-linking them.
  Future<void> unlink(String txnId) => _db.transaction(() async {
    final t = await _byId(txnId);
    final transferId = t?.transferId;
    if (transferId == null) return;
    final sides = await (_db.select(
      _db.transactions,
    )..where((o) => o.transferId.equals(transferId))).get();
    final resolver = await CategoryResolver.load(_db);
    final now = DateTime.now();
    for (final side in sides) {
      // A side the owner added only existed for this transfer.
      if (side.origin == TxnOrigin.user) {
        await (_db.update(
          _db.transactions,
        )..where((o) => o.id.equals(side.id))).write(
          TransactionsCompanion(
            deletedAt: Value(now),
            transferId: const Value(null),
            updatedAt: Value(now),
          ),
        );
        continue;
      }
      String? category;
      if (!side.userEdited && side.categoryId == transfersCategoryId) {
        final merchant = side.merchantId == null
            ? null
            : await (_db.select(
                _db.merchants,
              )..where((m) => m.id.equals(side.merchantId!))).getSingleOrNull();
        category = resolver.resolve(
          merchantKey: merchant?.normalizedKey,
          payee: side.payeeRaw,
          txnType: side.txnType,
        );
      }
      await (_db.update(
        _db.transactions,
      )..where((o) => o.id.equals(side.id))).write(
        TransactionsCompanion(
          transferId: const Value(null),
          autoTransferOff: const Value(true),
          categoryId: category == null ? const Value.absent() : Value(category),
          updatedAt: Value(now),
        ),
      );
    }
  });

  Future<void> _link(List<Transaction> sides) async {
    final id = newId();
    final now = DateTime.now();
    for (final side in sides) {
      await (_db.update(
        _db.transactions,
      )..where((o) => o.id.equals(side.id))).write(
        TransactionsCompanion(
          transferId: Value(id),
          autoTransferOff: const Value(false),
          // A category the user chose wins over the automatic one.
          categoryId: side.userEdited
              ? const Value.absent()
              : const Value(transfersCategoryId),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<Transaction?> _bestPartner(Transaction t) async {
    final candidates =
        await (_db.select(_db.transactions)..where(
              (o) =>
                  o.deletedAt.isNull() &
                  o.transferId.isNull() &
                  o.autoTransferOff.equals(false) &
                  o.accountId.isNotNull() &
                  o.accountId.equals(t.accountId!).not() &
                  o.amountMinor.equals(t.amountMinor) &
                  o.currency.equals(t.currency) &
                  o.direction.equalsValue(_opposite(t.direction)) &
                  o.occurredAt.isBetweenValues(
                    t.occurredAt.subtract(window),
                    t.occurredAt.add(window),
                  ),
            ))
            .get();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => _gap(t, a).compareTo(_gap(t, b)));
    return candidates.first;
  }

  bool _eligible(Transaction t) =>
      t.deletedAt == null &&
      t.transferId == null &&
      !t.autoTransferOff &&
      t.accountId != null;

  bool _matches(Transaction debit, Transaction credit) =>
      credit.direction == Direction.credit &&
      credit.accountId != debit.accountId &&
      credit.amountMinor == debit.amountMinor &&
      credit.currency == debit.currency &&
      _gap(debit, credit) <= window;

  Duration _gap(Transaction a, Transaction b) =>
      a.occurredAt.difference(b.occurredAt).abs();

  Direction _opposite(Direction d) =>
      d == Direction.debit ? Direction.credit : Direction.debit;

  Future<Transaction?> _byId(String id) => (_db.select(
    _db.transactions,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
}
