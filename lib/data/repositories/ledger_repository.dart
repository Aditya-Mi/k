import 'package:drift/drift.dart';
import 'package:rxdart/rxdart.dart';
import 'package:txn_parser/txn_parser.dart';

import '../db/app_database.dart';
import '../db/enums.dart';
import '../db/seed/seed_data.dart';
import 'ledger_models.dart';

/// Read models and edits for transactions, accounts and upcoming charges.
class LedgerRepository {
  LedgerRepository(this._db, {this.onRulesChanged});

  final AppDatabase _db;

  /// Lets ingestion drop its cached category rules.
  final void Function()? onRulesChanged;

  Stream<List<TxnView>> watchTransactions(TxnFilter f) {
    final t = _db.transactions;
    final m = _db.merchants;
    final query = _txnJoin()
      ..where(
        t.deletedAt.isNull() &
            t.occurredAt.isBiggerOrEqualValue(f.from) &
            t.occurredAt.isSmallerThanValue(f.to),
      )
      ..orderBy([OrderingTerm.desc(t.occurredAt)]);
    if (f.accountIds.isNotEmpty) query.where(t.accountId.isIn(f.accountIds));
    if (f.categoryIds.isNotEmpty) {
      query.where(t.categoryId.isIn(f.categoryIds));
    }
    if (f.direction != null) query.where(t.direction.equalsValue(f.direction));
    final q = f.query.trim();
    if (q.isNotEmpty) {
      final like = '%${q.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      query.where(
        m.displayName.like(like) |
            t.payeeRaw.like(like) |
            t.notes.like(like) |
            t.refNo.like(like),
      );
    }
    return query.watch().map((rows) => rows.map(_toView).toList());
  }

  /// Charges matched to subscriptions, newest first.
  Future<List<TxnView>> chargesOf(Iterable<String> subscriptionIds) =>
      (_txnJoin()
            ..where(
              _db.transactions.deletedAt.isNull() &
                  _db.transactions.subscriptionId.isIn(subscriptionIds),
            )
            ..orderBy([OrderingTerm.desc(_db.transactions.occurredAt)]))
          .get()
          .then((rows) => rows.map(_toView).toList());

  /// Rows logged from bank messages since [since] (live notifications).
  Future<List<TxnView>> loggedSince(DateTime since) =>
      (_txnJoin()
            ..where(
              _db.transactions.deletedAt.isNull() &
                  _db.transactions.origin.equalsValue(TxnOrigin.message) &
                  _db.transactions.createdAt.isBiggerOrEqualValue(since),
            )
            ..orderBy([OrderingTerm.asc(_db.transactions.occurredAt)]))
          .get()
          .then((rows) => rows.map(_toView).toList());

  Stream<List<TxnView>> watchCharges(String subscriptionId) =>
      (_txnJoin()
            ..where(
              _db.transactions.deletedAt.isNull() &
                  _db.transactions.subscriptionId.equals(subscriptionId),
            )
            ..orderBy([OrderingTerm.desc(_db.transactions.occurredAt)]))
          .watch()
          .map((rows) => rows.map(_toView).toList());

  Stream<TxnDetailView?> watchDetail(String id) {
    final query = _txnJoin()..where(_db.transactions.id.equals(id));
    return query
        .watchSingleOrNull()
        .map((r) => r == null ? null : _toView(r))
        .switchMap((view) {
          if (view == null) return Stream.value(null);
          return _watchSources(id).switchMap((own) {
            final partner = view.transferPartnerId;
            // A row added by the owner borrows its partner's message trail.
            if (own.isNotEmpty || partner == null) {
              return Stream.value(TxnDetailView(view, own));
            }
            return _watchSources(partner)
                .map((s) => TxnDetailView(view, s, sourcesFromPartner: true));
          });
        });
  }

  Stream<List<RawMessage>> _watchSources(String txnId) =>
      (_db.select(_db.rawMessages).join([
              innerJoin(
                _db.transactionSources,
                _db.transactionSources.rawMessageId.equalsExp(
                  _db.rawMessages.id,
                ),
              ),
            ])
            ..where(_db.transactionSources.transactionId.equals(txnId))
            ..orderBy([OrderingTerm.asc(_db.rawMessages.receivedAt)]))
          .watch()
          .map(
            (rows) => rows.map((r) => r.readTable(_db.rawMessages)).toList(),
          );

  /// Current balance per account id (see [computeBalance]).
  Stream<Map<String, AccountBalance>> watchBalances() {
    final t = _db.transactions;
    final txns = (_db.select(
      t,
    )..where((o) => o.deletedAt.isNull() & o.accountId.isNotNull())).watch();
    final accounts = (_db.select(
      _db.accounts,
    )..where((a) => a.deletedAt.isNull())).watch();
    return Rx.combineLatest2(accounts, txns, (accs, rows) {
      final byAccount = <String, List<Transaction>>{};
      for (final r in rows) {
        byAccount.putIfAbsent(r.accountId!, () => []).add(r);
      }
      final atm = [
        for (final r in rows)
          if (r.txnType == TxnType.atm && r.accountId != cashAccountId) r,
      ];
      return {
        for (final a in accs)
          a.id: ?(a.type == AccountType.cash
              ? computeCashBalance(a, byAccount[a.id] ?? const [], atm)
              : computeBalance(a, byAccount[a.id] ?? const [])),
      };
    });
  }

  /// An account the owner adds before any message names it (design 10c).
  /// Messages for this bank and last 4 then land on it. Returns null when
  /// the bank already has a live account with those digits.
  Future<String?> addAccount({
    required String bankId,
    required AccountType type,
    String? last4,
    String? nickname,
    int? balanceMinor,
    int? creditLimitMinor,
  }) => _db.transaction(() async {
    final digits = last4?.trim();
    final name = nickname?.trim();
    final now = DateTime.now();
    final existing = digits == null || digits.isEmpty
        ? null
        : await (_db.select(
                _db.accounts,
              )..where((a) => a.bankId.equals(bankId) & a.last4.equals(digits)))
              .getSingleOrNull();
    if (existing != null && existing.deletedAt == null) return null;
    final row = AccountsCompanion(
      bankId: Value(bankId),
      type: Value(type),
      last4: Value(digits == null || digits.isEmpty ? null : digits),
      nickname: Value(name == null || name.isEmpty ? null : name),
      autoCreated: const Value(false),
      manualBalanceMinor: Value(balanceMinor),
      manualBalanceAt: Value(balanceMinor == null ? null : now),
      creditLimitMinor: Value(creditLimitMinor),
      mergedIntoId: const Value(null),
      updatedAt: Value(now),
    );
    if (existing != null) {
      // A removed account with these digits (unique per bank) comes back.
      await (_db.update(_db.accounts)..where((a) => a.id.equals(existing.id)))
          .write(row.copyWith(deletedAt: const Value(null)));
      return existing.id;
    }
    return (await _db.into(_db.accounts).insertReturning(row)).id;
  });

  Future<void> renameAccount(String id, String? nickname) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          nickname: Value(
            nickname == null || nickname.trim().isEmpty
                ? null
                : nickname.trim(),
          ),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setCreditLimit(String id, int? minor) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          creditLimitMinor: Value(minor),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setManualBalance(String id, int minor, DateTime at) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          manualBalanceMinor: Value(minor),
          manualBalanceAt: Value(at),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Stream<List<AccountView>> watchAccounts() {
    final a = _db.accounts;
    final b = _db.banks;
    return (_db.select(a).join([innerJoin(b, b.id.equalsExp(a.bankId))])
          ..where(a.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(b.name), OrderingTerm.asc(a.last4)]))
        .watch()
        .map((rows) {
          // Folded accounts are hidden; their digits show on the target.
          final folded = <String, List<String>>{};
          for (final r in rows) {
            final acc = r.readTable(a);
            if (acc.mergedIntoId == null) continue;
            final kind =
                acc.type == AccountType.debitCard ||
                    acc.type == AccountType.creditCard
                ? 'card'
                : 'a/c';
            folded
                .putIfAbsent(acc.mergedIntoId!, () => [])
                .add('$kind ··${acc.last4 ?? '?'}');
          }
          return [
            for (final r in rows)
              if (r.readTable(a).mergedIntoId == null)
                _account(
                  r.readTable(a),
                  r.readTable(b),
                  includes: folded[r.readTable(a).id] ?? const [],
                ),
          ];
        });
  }

  /// Folds [sourceId] into [targetId]: its payments move over and future
  /// messages naming it are logged on the target.
  Future<void> mergeAccount(String sourceId, String targetId) =>
      _db.transaction(() async {
        final now = DateTime.now();
        await (_db.update(
          _db.transactions,
        )..where((t) => t.accountId.equals(sourceId))).write(
          TransactionsCompanion(
            accountId: Value(targetId),
            updatedAt: Value(now),
          ),
        );
        // Anything already folded into the source follows it.
        await (_db.update(_db.accounts)..where(
              (a) => a.mergedIntoId.equals(sourceId) | a.id.equals(sourceId),
            ))
            .write(
              AccountsCompanion(
                mergedIntoId: Value(targetId),
                updatedAt: Value(now),
              ),
            );
      });

  /// Bank id → display name ("AXIS" → "Axis Bank").
  Future<Map<String, String>> bankNames() async => {
    for (final b in await _db.select(_db.banks).get()) b.id: b.name,
  };

  /// Categories to pick from; [includeHidden] for filters over the past.
  Stream<List<Category>> watchCategories({bool includeHidden = false}) =>
      (_db.select(_db.categories)
            ..where(
              (c) =>
                  c.deletedAt.isNull() &
                  (includeHidden ? const Constant(true) : c.hidden.not()),
            )
            ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
          .watch();

  /// Every category with how many live payments it holds (Categories screen).
  Stream<List<(Category, int)>> watchCategoryUse() {
    final c = _db.categories;
    final t = _db.transactions;
    final n = t.id.count();
    return (_db.select(c).join([
            leftOuterJoin(
              t,
              t.categoryId.equalsExp(c.id) & t.deletedAt.isNull(),
            ),
          ])
          ..where(c.deletedAt.isNull())
          ..addColumns([n])
          ..groupBy([c.id])
          ..orderBy([OrderingTerm.asc(c.sortOrder)]))
        .watch()
        .map(
          (rows) => [for (final r in rows) (r.readTable(c), r.read(n) ?? 0)],
        );
  }

  /// Owner-made category, last in every list.
  Future<Category> addCategory(String name, String icon) async {
    final max = await _db
        .customSelect(
          'SELECT COALESCE(MAX(sort_order), 0) AS m FROM categories',
        )
        .getSingle();
    return _db
        .into(_db.categories)
        .insertReturning(
          CategoriesCompanion.insert(
            name: name.trim(),
            icon: icon,
            color: 0,
            sortOrder: Value(max.read<int>('m') + 1),
          ),
        );
  }

  Future<void> updateCategory(String id, {String? name, String? icon}) =>
      (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          icon: icon == null ? const Value.absent() : Value(icon),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setCategoryHidden(String id, bool hidden) async {
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        hidden: Value(hidden),
        updatedAt: Value(DateTime.now()),
      ),
    );
    onRulesChanged?.call();
  }

  /// How far ahead Upcoming looks. A yearly plan's alert (due months
  /// away) waits on the plan instead of sitting in Transactions.
  static const upcomingWindow = Duration(days: 30);

  /// AutoPay / mandate alerts due from today to [upcomingWindow] ahead.
  Stream<List<UpcomingView>> watchUpcoming(DateTime now) {
    final u = _db.upcomingCharges;
    final m = _db.merchants;
    final r = _db.rawMessages;
    final b = _db.banks;
    final today = DateTime(now.year, now.month, now.day);
    return (_db.select(u).join([
            leftOuterJoin(m, m.id.equalsExp(u.merchantId)),
            leftOuterJoin(r, r.id.equalsExp(u.rawMessageId)),
            leftOuterJoin(b, b.id.equalsExp(r.bankId)),
          ])
          ..where(
            u.deletedAt.isNull() &
                u.status.equalsValue(UpcomingChargeStatus.pending) &
                u.dueDate.isBetweenValues(
                  today,
                  today.add(upcomingWindow + const Duration(days: 1)),
                ),
          )
          ..orderBy([OrderingTerm.asc(u.dueDate)]))
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              () {
                final charge = row.readTable(u);
                final bank = row.readTableOrNull(b);
                return UpcomingView(
                  id: charge.id,
                  name: row.readTableOrNull(m)?.displayName ?? 'AutoPay',
                  amountMinor: charge.amountMinor,
                  dueDate: charge.dueDate,
                  bankShort: bank == null
                      ? null
                      : bankShortName(bank.id, bank.name),
                );
              }(),
          ],
        );
  }

  Stream<int> watchReviewCount() {
    final r = _db.rawMessages;
    final count = r.id.count();
    return (_db.selectOnly(r)
          ..addColumns([count])
          ..where(
            r.deletedAt.isNull() &
                r.status.equalsValue(RawMessageStatus.needsReview),
          ))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Sets a transaction's category. With [applyToMerchant], also teaches a
  /// merchant rule and re-files that merchant's other payments the owner
  /// has not categorized by hand (self transfers stay Transfers).
  Future<void> setCategory(
    String txnId,
    String categoryId, {
    bool applyToMerchant = false,
  }) => _db.transaction(() async {
    await _updateTxn(
      txnId,
      TransactionsCompanion(categoryId: Value(categoryId)),
    );
    if (!applyToMerchant) return;
    final txn = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(txnId))).getSingle();
    final merchantId = txn.merchantId;
    if (merchantId == null) return;
    final merchant = await (_db.select(
      _db.merchants,
    )..where((m) => m.id.equals(merchantId))).getSingle();
    await _db
        .into(_db.categoryRules)
        .insertOnConflictUpdate(
          CategoryRulesCompanion.insert(
            id: Value('mr_${merchant.normalizedKey}'),
            matchType: RuleMatchType.merchant,
            pattern: merchant.normalizedKey,
            categoryId: categoryId,
            priority: const Value(100),
            origin: RuleOrigin.user,
            updatedAt: Value(DateTime.now()),
          ),
        );
    await (_db.update(_db.transactions)..where(
          (t) =>
              t.merchantId.equals(merchantId) &
              t.userEdited.equals(false) &
              t.transferId.isNull() &
              t.deletedAt.isNull(),
        ))
        .write(
          TransactionsCompanion(
            categoryId: Value(categoryId),
            updatedAt: Value(DateTime.now()),
          ),
        );
    onRulesChanged?.call();
  });

  /// Merchant display name, for every payment to it.
  /// Renames the merchant everywhere. Giving it a name another merchant
  /// already has makes them one (Summary's top payees, subscriptions and
  /// "use for all" rules then see a single payee). Returns how many merged.
  Future<int> renameMerchant(String merchantId, String name) =>
      _db.transaction(() async {
        final clean = name.trim();
        await (_db.update(
          _db.merchants,
        )..where((m) => m.id.equals(merchantId))).write(
          MerchantsCompanion(
            displayName: Value(clean),
            updatedAt: Value(DateTime.now()),
          ),
        );
        final same =
            await (_db.select(_db.merchants)..where(
                  (m) =>
                      m.id.equals(merchantId).not() &
                      m.deletedAt.isNull() &
                      m.mergedIntoId.isNull() &
                      m.displayName.lower().equals(clean.toLowerCase()),
                ))
                .get();
        for (final o in same) {
          await _db.mergeMerchant(o.id, merchantId);
        }
        if (same.isNotEmpty) {
          _db.notifyUpdates({
            for (final t in <TableInfo>[
              _db.transactions,
              _db.merchants,
              _db.subscriptions,
              _db.upcomingCharges,
              _db.categoryRules,
            ])
              TableUpdate.onTable(t),
          });
          onRulesChanged?.call();
        }
        return same.length;
      });

  Future<void> setNote(String txnId, String? note) => _updateTxn(
    txnId,
    TransactionsCompanion(
      notes: Value(note == null || note.trim().isEmpty ? null : note.trim()),
    ),
  );

  /// Removes the transaction; its messages stay, marked so ingestion and the
  /// review queue leave them alone. Soft delete keeps the trail.
  Future<void> removeTransaction(
    String txnId, {
    required bool notATransaction,
  }) => _db.transaction(() async {
    final now = DateTime.now();
    await (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(txnId))).write(
      TransactionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        userEdited: const Value(true),
      ),
    );
    final rawIds = _db.selectOnly(_db.transactionSources)
      ..addColumns([_db.transactionSources.rawMessageId])
      ..where(_db.transactionSources.transactionId.equals(txnId));
    await (_db.update(
      _db.rawMessages,
    )..where((r) => r.id.isInQuery(rawIds))).write(
      RawMessagesCompanion(
        status: Value(
          notATransaction
              ? RawMessageStatus.nonTransaction
              : RawMessageStatus.ignored,
        ),
        parseNote: Value(
          notATransaction ? 'marked not a transaction' : 'transaction deleted',
        ),
        updatedAt: Value(now),
      ),
    );
  });

  Future<void> _updateTxn(String id, TransactionsCompanion c) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        c.copyWith(
          userEdited: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  JoinedSelectStatement<HasResultSet, dynamic> _txnJoin() {
    final t = _db.transactions;
    final a = _db.accounts;
    final b = _db.banks;
    final m = _db.merchants;
    final c = _db.categories;
    final s = _db.transactionSources;
    return _db.select(t).join([
        leftOuterJoin(a, a.id.equalsExp(t.accountId)),
        leftOuterJoin(b, b.id.equalsExp(a.bankId)),
        leftOuterJoin(m, m.id.equalsExp(t.merchantId)),
        leftOuterJoin(c, c.id.equalsExp(t.categoryId)),
        leftOuterJoin(s, s.transactionId.equalsExp(t.id)),
        // Other side of a self transfer, with its account.
        leftOuterJoin(
          _pt,
          _pt.transferId.equalsExp(t.transferId) &
              _pt.id.equalsExp(t.id).not() &
              _pt.deletedAt.isNull(),
        ),
        leftOuterJoin(_pa, _pa.id.equalsExp(_pt.accountId)),
        leftOuterJoin(_pb, _pb.id.equalsExp(_pa.bankId)),
        leftOuterJoin(
          _db.emis,
          _db.emis.id.equalsExp(t.emiId) & _db.emis.deletedAt.isNull(),
        ),
      ])
      ..addColumns([_sourceCount])
      ..groupBy([t.id]);
  }

  late final _sourceCount = _db.transactionSources.id.count(distinct: true);
  late final _pt = _db.alias(_db.transactions, 'pt');
  late final _pa = _db.alias(_db.accounts, 'pa');
  late final _pb = _db.alias(_db.banks, 'pb');

  TxnView _toView(TypedResult r) {
    final t = r.readTable(_db.transactions);
    final account = r.readTableOrNull(_db.accounts);
    final bank = r.readTableOrNull(_db.banks);
    final merchant = r.readTableOrNull(_db.merchants);
    final partner = r.readTableOrNull(_pt);
    final partnerAccount = r.readTableOrNull(_pa);
    final partnerBank = r.readTableOrNull(_pb);
    final emi = r.readTableOrNull(_db.emis);
    return TxnView(
      id: t.id,
      amountMinor: t.amountMinor,
      currency: t.currency,
      direction: t.direction,
      txnType: t.txnType,
      occurredAt: t.occurredAt,
      payee: merchant?.displayName ?? t.payeeRaw ?? _fallbackPayee(t),
      merchantId: merchant?.id,
      sourceCount: r.read(_sourceCount) ?? 0,
      account: account == null || bank == null ? null : _account(account, bank),
      category: r.readTableOrNull(_db.categories),
      balanceMinor: t.balanceMinor,
      notes: t.notes,
      refNo: t.refNo,
      transferId: t.transferId,
      origin: t.origin,
      transferPartnerId: partner?.id,
      subscriptionId: t.subscriptionId,
      emi: emi == null
          ? null
          : EmiLink(
              id: emi.id,
              name: emi.name,
              kind: emi.kind,
              isPurchase: emi.purchaseTransactionId == t.id,
              spread: emi.spread,
              count: emi.count,
              amountMinor: emi.amountMinor,
            ),
      partnerAccount: partnerAccount == null || partnerBank == null
          ? null
          : _account(partnerAccount, partnerBank),
    );
  }

  String _fallbackPayee(Transaction t) => switch (t.txnType) {
    TxnType.atm => 'ATM withdrawal',
    _ => t.direction == Direction.credit ? 'Money in' : 'Payment',
  };

  AccountView _account(Account a, Bank b, {List<String> includes = const []}) =>
      AccountView(
        id: a.id,
        bankId: b.id,
        bankName: b.name,
        type: a.type,
        last4: a.last4,
        nickname: a.nickname,
        includes: includes,
        creditLimitMinor: a.creditLimitMinor,
      );
}
