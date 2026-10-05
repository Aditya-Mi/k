import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:txn_parser/txn_parser.dart' show Direction, TxnType;

import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import '../repositories/ledger_models.dart';
import '../repositories/settings_repository.dart';
import 'emi_schedule.dart';

/// An EMI as Recurring, the card screen and the form show it.
class EmiView extends Equatable {
  const EmiView({
    required this.row,
    required this.reminderDays,
    required this.now,
    this.account,
    this.purchaseMinor,
  });

  final Emi row;

  /// Effective: the row's own, else the global default.
  final int reminderDays;

  /// The card it's billed on, or the account a loan is paid from.
  final AccountView? account;

  /// Card EMI: the purchase amount.
  final int? purchaseMinor;
  final DateTime now;

  String get id => row.id;
  String get name => row.name;
  bool get isCard => row.kind == EmiKind.card;

  EmiSchedule get schedule => EmiSchedule(
    firstDueAt: row.firstDueAt,
    count: row.count,
    amountMinor: row.amountMinor,
  );

  int get paid => schedule.paidBy(now);
  DateTime? get nextDueAt => schedule.nextAfter(now);
  DateTime get endsAt => schedule.lastDueAt;
  int get leftMinor => schedule.leftMinor(now);
  bool get done => paid >= row.count;

  @override
  List<Object?> get props => [row, reminderDays, account, purchaseMinor, now];
}

/// Card purchases converted to EMI and loans paid monthly: keeps their
/// instalments matched to debits and spreads spread purchases over months.
class EmiService {
  EmiService(this._db, this._settings, {this.onChanged});

  final AppDatabase _db;
  final SettingsRepository _settings;

  /// After anything that moves a reminder.
  final Future<void> Function()? onChanged;

  /// An instalment debit can land this far from its due day.
  static const matchWindow = Duration(days: 7);

  /// Banks round EMIs differently; allow this much either way.
  static const tolerance = 0.02;

  Future<int> defaultReminder() async =>
      await _settings.getInt('subscriptions.reminderDays') ?? 3;

  // ---------------------------------------------------------------- reads

  /// Active EMIs, soonest next instalment first.
  Stream<List<EmiView>> watch({String? accountId}) => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.emis,
          _db.accounts,
          _db.transactions,
          _db.appSettings,
        ]),
      )
      .cast<Object?>()
      .startWith(null)
      .debounceTime(const Duration(milliseconds: 30))
      .switchMap((_) => Stream.fromFuture(_views(accountId: accountId)));

  Stream<EmiView?> watchOne(String id) =>
      watch().map((all) => all.where((e) => e.id == id).firstOrNull);

  Future<List<EmiView>> _views({String? accountId}) async {
    final q = _db.select(_db.emis)
      ..where(
        (e) => e.deletedAt.isNull() & e.status.equalsValue(EmiStatus.active),
      );
    if (accountId != null) q.where((e) => e.accountId.equals(accountId));
    final rows = await q.get();
    final fallback = await defaultReminder();
    final now = DateTime.now();
    final accounts = <String, AccountView>{};
    for (final r in await (_db.select(_db.accounts).join([
      innerJoin(_db.banks, _db.banks.id.equalsExp(_db.accounts.bankId)),
    ])).get()) {
      final a = r.readTable(_db.accounts);
      final b = r.readTable(_db.banks);
      accounts[a.id] = AccountView(
        id: a.id,
        bankId: b.id,
        bankName: b.name,
        type: a.type,
        last4: a.last4,
        nickname: a.nickname,
        creditLimitMinor: a.creditLimitMinor,
      );
    }
    final purchaseIds = rows.map((r) => r.purchaseTransactionId).nonNulls;
    final purchases = {
      for (final t in await (_db.select(
        _db.transactions,
      )..where((t) => t.id.isIn(purchaseIds))).get())
        t.id: t.amountMinor,
    };
    final views = [
      for (final r in rows)
        EmiView(
          row: r,
          reminderDays: r.reminderDays ?? fallback,
          now: now,
          account: accounts[r.accountId],
          purchaseMinor: purchases[r.purchaseTransactionId],
        ),
    ];
    final far = DateTime(9999);
    views.sort((a, b) => (a.nextDueAt ?? far).compareTo(b.nextDueAt ?? far));
    return views;
  }

  /// Instalments of spread card EMIs due in [month] (up to now) that no
  /// matched debit covers: k counts them as spent in that month. Returned as
  /// rows for the month panel and Summary; never listed or stored.
  Future<List<TxnView>> virtualInstalments(
    List<DateTime> months, {
    DateTime? now,
  }) async {
    final rows =
        await (_db.select(_db.emis)..where(
              (e) =>
                  e.deletedAt.isNull() &
                  e.kind.equalsValue(EmiKind.card) &
                  e.spread.equals(true),
            ))
            .get();
    if (rows.isEmpty) return const [];
    final at = now ?? DateTime.now();
    final linked =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.emiId.isIn(rows.map((r) => r.id)) &
                  t.direction.equalsValue(Direction.debit),
            ))
            .get();
    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };
    final out = <TxnView>[];
    for (final e in rows) {
      final s = EmiSchedule(
        firstDueAt: e.firstDueAt,
        count: e.count,
        amountMinor: e.amountMinor,
      );
      final mine = linked.where(
        (t) => t.emiId == e.id && t.id != e.purchaseTransactionId,
      );
      for (final month in months) {
        for (final (n, due) in s.dueIn(month, at)) {
          final covered = mine.any(
            (t) =>
                t.occurredAt.year == due.year &&
                t.occurredAt.month == due.month,
          );
          if (covered) continue;
          out.add(
            TxnView(
              id: 'emi:${e.id}:$n',
              amountMinor: e.amountMinor,
              currency: e.currency,
              direction: Direction.debit,
              txnType: TxnType.card,
              occurredAt: due,
              payee: e.name,
              sourceCount: 0,
              category: categories[e.categoryId],
              origin: TxnOrigin.user,
            ),
          );
        }
      }
    }
    return out;
  }

  // -------------------------------------------------------------- writes

  /// "Convert to EMI" on a card payment (design 13b).
  Future<String> convertPurchase({
    required String transactionId,
    required int count,
    required int amountMinor,
    required DateTime firstDueAt,
    bool spread = true,
  }) async {
    final id = await _db.transaction(() async {
      final t = await (_db.select(
        _db.transactions,
      )..where((o) => o.id.equals(transactionId))).getSingle();
      final merchant = t.merchantId == null
          ? null
          : await (_db.select(
              _db.merchants,
            )..where((m) => m.id.equals(t.merchantId!))).getSingleOrNull();
      final row = await _db
          .into(_db.emis)
          .insertReturning(
            EmisCompanion.insert(
              name: merchant?.displayName ?? t.payeeRaw ?? 'Card purchase',
              kind: EmiKind.card,
              accountId: Value(t.accountId),
              purchaseTransactionId: Value(t.id),
              amountMinor: amountMinor,
              currency: Value(t.currency),
              count: count,
              firstDueAt: firstDueAt,
              spread: Value(spread),
              status: EmiStatus.active,
              categoryId: Value(t.categoryId),
            ),
          );
      await (_db.update(
        _db.transactions,
      )..where((o) => o.id.equals(t.id))).write(
        TransactionsCompanion(
          emiId: Value(row.id),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return row.id;
    });
    await refresh();
    return id;
  }

  /// "Add a loan EMI" (design 13c): [paid] instalments already made, the
  /// next due [nextDueAt].
  Future<String> addLoan({
    required String name,
    required String? accountId,
    required int amountMinor,
    required int count,
    required int paid,
    required DateTime nextDueAt,
    int? reminderDays,
  }) async {
    final row = await _db
        .into(_db.emis)
        .insertReturning(
          EmisCompanion.insert(
            name: name,
            kind: EmiKind.loan,
            accountId: Value(accountId),
            amountMinor: amountMinor,
            count: count,
            firstDueAt: EmiSchedule.firstFrom(nextDueAt, paid),
            status: EmiStatus.active,
            reminderDays: Value(reminderDays),
            categoryId: const Value('cat_bills'),
          ),
        );
    await refresh();
    return row.id;
  }

  /// Edits from the EMI form. [paid] + [nextDueAt] move the schedule.
  Future<void> update(
    String id, {
    String? name,
    int? amountMinor,
    int? count,
    int? paid,
    DateTime? nextDueAt,
    bool? spread,
    int? Function()? reminderDays,
    String? Function()? accountId,
  }) async {
    final e = await (_db.select(
      _db.emis,
    )..where((o) => o.id.equals(id))).getSingle();
    DateTime? first;
    if (paid != null && nextDueAt != null) {
      first = EmiSchedule.firstFrom(nextDueAt, paid);
    } else if (nextDueAt != null) {
      first = EmiSchedule.firstFrom(
        nextDueAt,
        EmiSchedule(
          firstDueAt: e.firstDueAt,
          count: e.count,
          amountMinor: e.amountMinor,
        ).paidBy(DateTime.now()),
      );
    }
    await (_db.update(_db.emis)..where((o) => o.id.equals(id))).write(
      EmisCompanion(
        name: name == null ? const Value.absent() : Value(name),
        amountMinor: amountMinor == null
            ? const Value.absent()
            : Value(amountMinor),
        count: count == null ? const Value.absent() : Value(count),
        firstDueAt: first == null ? const Value.absent() : Value(first),
        spread: spread == null ? const Value.absent() : Value(spread),
        reminderDays: reminderDays == null
            ? const Value.absent()
            : Value(reminderDays()),
        accountId: accountId == null
            ? const Value.absent()
            : Value(accountId()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await refresh();
  }

  /// Stops tracking: the purchase counts once again, instalments unlink.
  Future<void> remove(String id) async {
    await _db.transaction(() async {
      final now = DateTime.now();
      await (_db.update(
        _db.transactions,
      )..where((t) => t.emiId.equals(id))).write(
        TransactionsCompanion(emiId: const Value(null), updatedAt: Value(now)),
      );
      await (_db.update(_db.emis)..where((e) => e.id.equals(id))).write(
        EmisCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
    await onChanged?.call();
  }

  // -------------------------------------------------------------- refresh

  /// Links new debits to instalments and closes finished EMIs.
  Future<void> refresh({DateTime? now}) async {
    final at = now ?? DateTime.now();
    await _db.transaction(() async {
      final emis =
          await (_db.select(_db.emis)..where(
                (e) =>
                    e.deletedAt.isNull() &
                    e.status.equalsValue(EmiStatus.active),
              ))
              .get();
      for (final e in emis) {
        await _match(e);
        final s = EmiSchedule(
          firstDueAt: e.firstDueAt,
          count: e.count,
          amountMinor: e.amountMinor,
        );
        // A month past the last instalment, it's done.
        if (at.isAfter(addMonths(s.lastDueAt, 1))) {
          await (_db.update(_db.emis)..where((o) => o.id.equals(e.id))).write(
            EmisCompanion(
              status: const Value(EmiStatus.closed),
              updatedAt: Value(at),
            ),
          );
        }
      }
    });
    await onChanged?.call();
  }

  /// Unlinked debits on the EMI's account, near an instalment's due day that
  /// has no debit yet, within [tolerance] of the amount.
  Future<void> _match(Emi e) async {
    if (e.accountId == null) return;
    final s = EmiSchedule(
      firstDueAt: e.firstDueAt,
      count: e.count,
      amountMinor: e.amountMinor,
    );
    final lo = (e.amountMinor * (1 - tolerance)).floor();
    final hi = (e.amountMinor * (1 + tolerance)).ceil();
    final from = s.dueAt(0).subtract(matchWindow);
    final to = s.lastDueAt.add(matchWindow);
    final linked =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.emiId.equals(e.id) &
                  t.id.equals(e.purchaseTransactionId ?? '').not(),
            ))
            .get();
    final candidates =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.emiId.isNull() &
                  t.transferId.isNull() &
                  t.accountId.equals(e.accountId!) &
                  t.direction.equalsValue(Direction.debit) &
                  t.amountMinor.isBetweenValues(lo, hi) &
                  t.occurredAt.isBetweenValues(from, to),
            ))
            .get();
    for (var n = 0; n < e.count; n++) {
      final due = s.dueAt(n);
      bool near(Transaction t) =>
          t.occurredAt.difference(due).abs() <= matchWindow;
      if (linked.any(near)) continue;
      final hit = candidates.where(near).toList()
        ..sort(
          (a, b) => a.occurredAt
              .difference(due)
              .abs()
              .compareTo(b.occurredAt.difference(due).abs()),
        );
      if (hit.isEmpty) continue;
      final t = hit.first;
      candidates.remove(t);
      linked.add(t);
      await (_db.update(
        _db.transactions,
      )..where((o) => o.id.equals(t.id))).write(
        TransactionsCompanion(
          emiId: Value(e.id),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }
}
