import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../core/ids.dart';
import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import '../db/seed/seed_data.dart';
import 'card_bill.dart';
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
    if (partner != null) {
      await _link([t, partner]);
      return true;
    }
    // A card's "payment received" joins a bill payment already logged alone.
    if (t.direction == Direction.credit && await _isCreditCard(t.accountId)) {
      final bill = await _loneCardBill(t);
      if (bill != null) {
        await _join(t, bill.transferId!);
        return true;
      }
    }
    return false;
  }

  /// A debit that pays a credit card bill ([looksLikeCardBill] on its payee
  /// or message [text]) becomes a self transfer to that card. When the card
  /// is in k (named by its digits, or the only one) it gets the card's
  /// matching credit, or a card side added by k; else it's logged alone.
  /// Returns true if marked.
  ///
  /// [force]: the owner said so ("Card bill payment" on detail), so the
  /// payee doesn't have to look like one and an unlinked row qualifies.
  Future<bool> markCardBill(
    String txnId, {
    String text = '',
    bool force = false,
  }) async {
    final t = await _byId(txnId);
    if (t == null ||
        t.deletedAt != null ||
        t.transferId != null ||
        t.accountId == null ||
        t.accountId == cashAccountId ||
        (!force && t.autoTransferOff) ||
        t.direction != Direction.debit) {
      return false;
    }
    if (await _isCreditCard(t.accountId)) return false;
    final merchant = t.merchantId == null
        ? null
        : await (_db.select(
            _db.merchants,
          )..where((m) => m.id.equals(t.merchantId!))).getSingleOrNull();
    final payee = [t.payeeRaw, merchant?.displayName].nonNulls.join(' ');
    if (!force && !looksLikeCardBill(payee, text)) return false;
    final own = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(t.accountId!))).getSingleOrNull();
    final cards =
        await (_db.select(_db.accounts)..where(
              (a) =>
                  a.deletedAt.isNull() &
                  a.mergedIntoId.isNull() &
                  a.type.equalsValue(AccountType.creditCard),
            ))
            .get();
    final named = maskedDigits(text, own: own?.last4);
    final card =
        cards.where((c) => named.contains(c.last4)).firstOrNull ??
        (cards.length == 1 ? cards.single : null);
    Transaction? credit;
    if (card != null) {
      const span = Duration(days: 3);
      final rows =
          await (_db.select(_db.transactions)..where(
                (o) =>
                    o.deletedAt.isNull() &
                    o.transferId.isNull() &
                    o.autoTransferOff.equals(false) &
                    o.accountId.equals(card.id) &
                    o.direction.equalsValue(Direction.credit) &
                    o.amountMinor.equals(t.amountMinor) &
                    o.occurredAt.isBetweenValues(
                      t.occurredAt.subtract(span),
                      t.occurredAt.add(span),
                    ),
              ))
              .get();
      rows.sort((a, b) => _gap(t, a).compareTo(_gap(t, b)));
      // No "payment received" yet: add the card's side so its available
      // limit moves now. A late bank message becomes this row.
      credit =
          rows.firstOrNull ??
          await _db
              .into(_db.transactions)
              .insertReturning(
                TransactionsCompanion.insert(
                  accountId: Value(card.id),
                  amountMinor: t.amountMinor,
                  currency: Value(t.currency),
                  direction: Direction.credit,
                  txnType: t.txnType,
                  occurredAt: t.occurredAt,
                  categoryId: const Value(cardBillCategoryId),
                  origin: const Value(TxnOrigin.user),
                ),
              );
    }
    await _link([t, ?credit], category: cardBillCategoryId);
    return true;
  }

  /// Backfill: bill payments logged before k knew them, reading each
  /// candidate's bank messages too. Returns how many were marked.
  Future<int> markCardBillsAll() async {
    final rows = await _db
        .customSelect(
          'SELECT t.id, group_concat(r.body, \' \') AS text '
          'FROM transactions t '
          'JOIN accounts a ON a.id = t.account_id '
          'LEFT JOIN transaction_sources s ON s.transaction_id = t.id '
          'LEFT JOIN raw_messages r ON r.id = s.raw_message_id '
          'WHERE t.deleted_at IS NULL AND t.transfer_id IS NULL '
          "AND t.auto_transfer_off = 0 AND t.direction = 'debit' "
          "AND a.type NOT IN ('creditCard', 'cash') "
          'GROUP BY t.id',
        )
        .get();
    var n = 0;
    for (final r in rows) {
      final text = r.readNullable<String>('text') ?? '';
      if (await markCardBill(r.read<String>('id'), text: text)) n++;
    }
    return n;
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
                    t.accountId.isNotNull() &
                    t.accountId.equals(cashAccountId).not(),
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
    return rows
        .where(
          (o) => o.accountId != t.accountId && o.accountId != cashAccountId,
        )
        .toList()
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
      if (!side.userEdited &&
          (side.categoryId == transfersCategoryId ||
              side.categoryId == cardBillCategoryId)) {
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

  Future<void> _link(List<Transaction> sides, {String? category}) async {
    final id = newId();
    final now = DateTime.now();
    category ??= await _categoryFor(sides);
    for (final side in sides) {
      await (_db.update(
        _db.transactions,
      )..where((o) => o.id.equals(side.id))).write(
        TransactionsCompanion(
          transferId: Value(id),
          autoTransferOff: const Value(false),
          // A category the user chose wins over the automatic one.
          categoryId: side.userEdited ? const Value.absent() : Value(category),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// Adds [t] to a transfer whose other side was logged alone.
  Future<void> _join(Transaction t, String transferId) =>
      (_db.update(_db.transactions)..where((o) => o.id.equals(t.id))).write(
        TransactionsCompanion(
          transferId: Value(transferId),
          autoTransferOff: const Value(false),
          categoryId: t.userEdited
              ? const Value.absent()
              : const Value(cardBillCategoryId),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Money moving to or from a credit card is a card bill payment.
  Future<String> _categoryFor(List<Transaction> sides) async {
    for (final s in sides) {
      if (await _isCreditCard(s.accountId)) return cardBillCategoryId;
    }
    return transfersCategoryId;
  }

  Future<bool> _isCreditCard(String? accountId) async {
    if (accountId == null) return false;
    final a = await (_db.select(
      _db.accounts,
    )..where((o) => o.id.equals(accountId))).getSingleOrNull();
    return a?.type == AccountType.creditCard;
  }

  /// A bill payment logged alone (its card side missing) that [credit] on a
  /// card completes: same amount, within ±3 days, closest first.
  Future<Transaction?> _loneCardBill(Transaction credit) async {
    const span = Duration(days: 3);
    final rows =
        await (_db.select(_db.transactions)..where(
              (o) =>
                  o.deletedAt.isNull() &
                  o.transferId.isNotNull() &
                  o.categoryId.equals(cardBillCategoryId) &
                  o.direction.equalsValue(Direction.debit) &
                  o.amountMinor.equals(credit.amountMinor) &
                  o.occurredAt.isBetweenValues(
                    credit.occurredAt.subtract(span),
                    credit.occurredAt.add(span),
                  ),
            ))
            .get();
    final alone = <Transaction>[];
    for (final r in rows) {
      final sides =
          await (_db.select(_db.transactions)..where(
                (o) =>
                    o.transferId.equals(r.transferId!) & o.deletedAt.isNull(),
              ))
              .get();
      if (sides.length == 1) alone.add(r);
    }
    alone.sort((a, b) => _gap(credit, a).compareTo(_gap(credit, b)));
    return alone.firstOrNull;
  }

  Future<Transaction?> _bestPartner(Transaction t) async {
    final candidates =
        await (_db.select(_db.transactions)..where(
              (o) =>
                  o.deletedAt.isNull() &
                  o.transferId.isNull() &
                  o.autoTransferOff.equals(false) &
                  o.accountId.isNotNull() &
                  o.accountId.equals(cashAccountId).not() &
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
      t.accountId != null &&
      // Cash moves through ATM withdrawals, never self transfers.
      t.accountId != cashAccountId;

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
