import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:txn_parser/txn_parser.dart' show Direction;

import '../db/app_database.dart' hide ParserTemplate, SenderRule;
import '../db/enums.dart';
import '../repositories/ledger_models.dart';
import '../repositories/ledger_repository.dart';
import '../repositories/settings_repository.dart';
import 'recurrence.dart';

/// A subscription as the list and detail show it.
class SubscriptionView extends Equatable {
  const SubscriptionView({
    required this.row,
    required this.reminderDays,
    required this.autoPay,
    this.account,
    this.chargeDates = const [],
  });

  final Subscription row;

  /// Effective: the row's own, else the global default.
  final int reminderDays;

  /// Charged by an AutoPay / e-mandate (a bank alert names it).
  final bool autoPay;

  /// Account of the newest matched charge.
  final AccountView? account;

  /// Matched charges, oldest first (the suggestion card lists them).
  final List<DateTime> chargeDates;

  String get id => row.id;
  String get name => row.name;
  int get amountMinor => row.amountMinor;
  bool get suggested => row.status == SubscriptionStatus.suggested;
  bool get usesDefaultReminder => row.reminderDays == null;

  /// Previous price, when the newest charge changed it.
  int? get previousAmountMinor => row.priceChanged ? row.lastAmountMinor : null;
  bool get priceUp =>
      previousAmountMinor != null && row.amountMinor > previousAmountMinor!;

  int get perMonthMinor =>
      monthlyMinor(row.amountMinor, row.frequency, row.intervalDays);

  @override
  List<Object?> get props => [row, reminderDays, autoPay, account, chargeDates];
}

class SubscriptionsOverview extends Equatable {
  const SubscriptionsOverview({
    required this.suggestions,
    required this.active,
    required this.reminderDays,
  });

  final List<SubscriptionView> suggestions;

  /// Soonest next charge first.
  final List<SubscriptionView> active;

  /// Global default.
  final int reminderDays;

  int get perMonthMinor => active.fold(0, (s, v) => s + v.perMonthMinor);
  int get perYearMinor => perMonthMinor * 12;

  @override
  List<Object?> get props => [suggestions, active, reminderDays];
}

/// Finds subscriptions in the ledger, keeps them matched to new charges and
/// AutoPay alerts, and holds the owner's edits.
class SubscriptionService {
  SubscriptionService(this._db, this._ledger, this._settings, {this.onChanged});

  final AppDatabase _db;
  final LedgerRepository _ledger;
  final SettingsRepository _settings;

  /// After anything that moves a reminder (reschedule notifications).
  final Future<void> Function()? onChanged;

  static const reminderKey = 'subscriptions.reminderDays';
  static const toleranceKey = 'subscriptions.amountTolerancePct';

  /// A charge this far from the expected day still counts at a new price.
  static const priceChangeWindow = Duration(days: 7);

  /// AutoPay alert and its debit can land a few days apart.
  static const mandateMatchWindow = Duration(days: 3);

  Future<int> defaultReminderDays() async =>
      await _settings.getInt(reminderKey) ?? 3;

  Future<double> _tolerance() async =>
      (await _settings.getInt(toleranceKey) ?? 10) / 100;

  // ---------------------------------------------------------------- reads

  Stream<SubscriptionsOverview> watch() =>
      _changes().switchMap((_) => Stream.fromFuture(_overview()));

  Stream<SubscriptionView?> watchOne(String id) =>
      _changes().switchMap((_) => Stream.fromFuture(_one(id)));

  Stream<Object?> _changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.subscriptions,
          _db.transactions,
          _db.accounts,
          _db.upcomingCharges,
          _db.appSettings,
        ]),
      )
      .cast<Object?>()
      .startWith(null)
      .debounceTime(const Duration(milliseconds: 30));

  Future<SubscriptionsOverview> _overview() async {
    final rows =
        await (_db.select(_db.subscriptions)..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.status.isInValues([
                    SubscriptionStatus.suggested,
                    SubscriptionStatus.active,
                  ]),
            ))
            .get();
    final views = await _views(rows);
    final far = DateTime(9999);
    final active =
        views.where((v) => v.row.status == SubscriptionStatus.active).toList()
          ..sort(
            (a, b) => (a.row.nextExpectedAt ?? far).compareTo(
              b.row.nextExpectedAt ?? far,
            ),
          );
    return SubscriptionsOverview(
      suggestions: views.where((v) => v.suggested).toList(),
      active: active,
      reminderDays: await defaultReminderDays(),
    );
  }

  Future<SubscriptionView?> _one(String id) async {
    final row = await (_db.select(
      _db.subscriptions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return (await _views([row])).single;
  }

  Future<List<SubscriptionView>> _views(List<Subscription> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r.id).toList();
    final charges = await _ledger.chargesOf(ids);
    final mandates = await (_db.select(
      _db.upcomingCharges,
    )..where((u) => u.deletedAt.isNull() & u.subscriptionId.isIn(ids))).get();
    final mandateSubs = {for (final u in mandates) u.subscriptionId};
    final fallback = await defaultReminderDays();
    final bySub = <String, List<TxnView>>{};
    // chargesOf has no subscription column in the view; look it up.
    final links = await (_db.select(
      _db.transactions,
    )..where((t) => t.subscriptionId.isIn(ids) & t.deletedAt.isNull())).get();
    final subOf = {for (final t in links) t.id: t.subscriptionId!};
    for (final c in charges) {
      (bySub[subOf[c.id]!] ??= []).add(c);
    }
    return [
      for (final r in rows)
        SubscriptionView(
          row: r,
          reminderDays: r.reminderDays ?? fallback,
          autoPay:
              r.source == SubscriptionSource.mandate ||
              mandateSubs.contains(r.id),
          account: bySub[r.id]?.first.account,
          chargeDates: [
            for (final c in (bySub[r.id] ?? const <TxnView>[]).reversed)
              c.occurredAt,
          ],
        ),
    ];
  }

  // -------------------------------------------------------------- refresh

  /// Brings everything up to date: expire old AutoPay alerts, match new
  /// charges to tracked plans, attach alerts, then look for new candidates.
  Future<void> refresh({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final tolerance = await _tolerance();
    await _db.transaction(() async {
      await _expireMandates(at);
      await _matchCharges(tolerance);
      await _matchFirstCharge(tolerance);
      await _attachMandates(tolerance);
      await _detect(at, tolerance);
    });
    await onChanged?.call();
  }

  Future<void> _expireMandates(DateTime now) async {
    final cutoff = now.subtract(mandateMatchWindow);
    await (_db.update(_db.upcomingCharges)..where(
          (u) =>
              u.status.equalsValue(UpcomingChargeStatus.pending) &
              u.dueDate.isSmallerThanValue(cutoff),
        ))
        .write(
          UpcomingChargesCompanion(
            status: const Value(UpcomingChargeStatus.expired),
            updatedAt: Value(now),
          ),
        );
  }

  /// Unlinked debits to the merchant of a tracked plan: within tolerance of
  /// the price anywhere after the last charge, or at any price near the
  /// expected day (a price change).
  Future<void> _matchCharges(double tolerance) async {
    final subs =
        await (_db.select(_db.subscriptions)..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.merchantId.isNotNull() &
                  s.status.equalsValue(SubscriptionStatus.active),
            ))
            .get();
    for (var sub in subs) {
      final cycle = Duration(
        days: cycleDays(sub.frequency, custom: sub.intervalDays),
      );
      final after = sub.lastChargedAt?.add(cycle ~/ 2);
      final candidates =
          await (_db.select(_db.transactions)
                ..where(
                  (t) =>
                      t.deletedAt.isNull() &
                      t.subscriptionId.isNull() &
                      t.transferId.isNull() &
                      t.merchantId.equals(sub.merchantId!) &
                      t.direction.equalsValue(Direction.debit),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
              .get();
      for (final t in candidates) {
        if (after != null && t.occurredAt.isBefore(after)) continue;
        final expected = sub.nextExpectedAt;
        final onTime =
            expected != null &&
            t.occurredAt.difference(expected).abs() <= priceChangeWindow;
        final samePrice = withinTolerance(
          t.amountMinor,
          sub.amountMinor,
          tolerance,
        );
        if (!samePrice && !onTime) continue;
        sub = await _charge(sub, t);
      }
    }
  }

  /// A plan added by hand has no payee yet. Its first charge is a debit
  /// within [priceChangeWindow] of the expected day, about the same amount,
  /// whose payee shares a word with the plan's name ("Apple Music" →
  /// "APPLE MEDIA SERVICES"). From then on it follows that payee.
  Future<void> _matchFirstCharge(double tolerance) async {
    final subs =
        await (_db.select(_db.subscriptions)..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.merchantId.isNull() &
                  s.nextExpectedAt.isNotNull() &
                  s.status.equalsValue(SubscriptionStatus.active),
            ))
            .get();
    for (final sub in subs) {
      final words = nameWords(sub.name);
      if (words.isEmpty) continue;
      final due = sub.nextExpectedAt!;
      final rows =
          await (_db.select(_db.transactions).join([
                leftOuterJoin(
                  _db.merchants,
                  _db.merchants.id.equalsExp(_db.transactions.merchantId),
                ),
              ])..where(
                _db.transactions.deletedAt.isNull() &
                    _db.transactions.subscriptionId.isNull() &
                    _db.transactions.transferId.isNull() &
                    _db.transactions.merchantId.isNotNull() &
                    _db.transactions.direction.equalsValue(Direction.debit) &
                    _db.transactions.occurredAt.isBetweenValues(
                      due.subtract(priceChangeWindow),
                      due.add(priceChangeWindow),
                    ),
              ))
              .get();
      Transaction? best;
      for (final r in rows) {
        final t = r.readTable(_db.transactions);
        final m = r.readTableOrNull(_db.merchants);
        final payee = nameWords('${m?.displayName ?? ''} ${t.payeeRaw ?? ''}');
        if (!words.any(payee.contains)) continue;
        if (!withinTolerance(t.amountMinor, sub.amountMinor, tolerance)) {
          continue;
        }
        if (best == null ||
            t.occurredAt.difference(due).abs() <
                best.occurredAt.difference(due).abs()) {
          best = t;
        }
      }
      if (best == null) continue;
      final linked = sub.copyWith(merchantId: Value(best.merchantId));
      await _db.update(_db.subscriptions).replace(linked);
      await _charge(linked, best);
    }
  }

  /// Links [t] to [sub] and moves the plan on one cycle.
  Future<Subscription> _charge(Subscription sub, Transaction t) async {
    final now = DateTime.now();
    await (_db.update(_db.transactions)..where((x) => x.id.equals(t.id))).write(
      TransactionsCompanion(
        subscriptionId: Value(sub.id),
        updatedAt: Value(now),
      ),
    );
    final changed = t.amountMinor != sub.amountMinor;
    final next = nextCharge(
      t.occurredAt,
      sub.frequency,
      customDays: sub.intervalDays,
    );
    final updated = sub.copyWith(
      amountMinor: t.amountMinor,
      lastAmountMinor: Value(changed ? sub.amountMinor : sub.lastAmountMinor),
      priceChanged: changed,
      lastChargedAt: Value(t.occurredAt),
      nextExpectedAt: Value(next),
      updatedAt: now,
    );
    await _db.update(_db.subscriptions).replace(updated);
    // The AutoPay alert this charge settles.
    await (_db.update(_db.upcomingCharges)..where(
          (u) =>
              u.status.equalsValue(UpcomingChargeStatus.pending) &
              (u.subscriptionId.equals(sub.id) |
                  (sub.merchantId == null
                      ? const Constant(false)
                      : u.merchantId.equals(sub.merchantId!))) &
              u.dueDate.isBetweenValues(
                t.occurredAt.subtract(mandateMatchWindow),
                t.occurredAt.add(mandateMatchWindow),
              ),
        ))
        .write(
          UpcomingChargesCompanion(
            status: const Value(UpcomingChargeStatus.matched),
            matchedTransactionId: Value(t.id),
            updatedAt: Value(now),
          ),
        );
    return updated;
  }

  /// Pending AutoPay alerts: attach to the merchant's plan (its next charge
  /// is the alert's due date), or suggest one.
  Future<void> _attachMandates(double tolerance) async {
    final pending =
        await (_db.select(_db.upcomingCharges)..where(
              (u) =>
                  u.deletedAt.isNull() &
                  u.subscriptionId.isNull() &
                  u.merchantId.isNotNull() &
                  u.status.equalsValue(UpcomingChargeStatus.pending),
            ))
            .get();
    for (final u in pending) {
      final existing =
          await (_db.select(_db.subscriptions)
                ..where(
                  (s) =>
                      s.deletedAt.isNull() & s.merchantId.equals(u.merchantId!),
                )
                ..orderBy([(s) => OrderingTerm.desc(s.updatedAt)])
                ..limit(1))
              .getSingleOrNull();
      if (existing != null && existing.status == SubscriptionStatus.dismissed) {
        continue;
      }
      var sub = existing;
      if (sub == null || sub.status == SubscriptionStatus.cancelled) {
        sub = await _insertSuggestion(
          merchantId: u.merchantId!,
          amountMinor: u.amountMinor,
          frequency: SubscriptionFrequency.monthly,
          source: SubscriptionSource.mandate,
          next: u.dueDate,
        );
      }
      await (_db.update(
        _db.upcomingCharges,
      )..where((x) => x.id.equals(u.id))).write(
        UpcomingChargesCompanion(
          subscriptionId: Value(sub.id),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final due = sub.nextExpectedAt;
      if (due == null || u.dueDate.isAfter(due.subtract(mandateMatchWindow))) {
        await (_db.update(
          _db.subscriptions,
        )..where((s) => s.id.equals(sub!.id))).write(
          SubscriptionsCompanion(
            nextExpectedAt: Value(u.dueDate),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
  }

  /// Repeating debits at a merchant with no plan yet → suggestion.
  Future<void> _detect(DateTime now, double tolerance) async {
    final since = now.subtract(const Duration(days: 400));
    final debits =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.subscriptionId.isNull() &
                  t.transferId.isNull() &
                  t.merchantId.isNotNull() &
                  t.direction.equalsValue(Direction.debit) &
                  t.occurredAt.isBiggerOrEqualValue(since),
            ))
            .get();
    final subs = await (_db.select(
      _db.subscriptions,
    )..where((s) => s.deletedAt.isNull() & s.merchantId.isNotNull())).get();
    // Newest plan per merchant decides: suggested/active/dismissed block;
    // cancelled only blocks the charges it already covered.
    final latest = <String, Subscription>{};
    for (final s in subs) {
      final cur = latest[s.merchantId!];
      if (cur == null || s.updatedAt.isAfter(cur.updatedAt)) {
        latest[s.merchantId!] = s;
      }
    }
    final byMerchant = <String, List<Transaction>>{};
    for (final t in debits) {
      (byMerchant[t.merchantId!] ??= []).add(t);
    }
    for (final MapEntry(key: merchantId, value: txns) in byMerchant.entries) {
      final plan = latest[merchantId];
      if (plan != null && plan.status != SubscriptionStatus.cancelled) {
        continue;
      }
      final from = plan == null ? null : plan.lastChargedAt ?? plan.updatedAt;
      final run = detectRecurrence([
        for (final t in txns)
          if (from == null || t.occurredAt.isAfter(from))
            Charge(t.id, t.amountMinor, t.occurredAt),
      ], tolerance: tolerance);
      if (run == null) continue;
      // Still running: the newest charge is within ~1.5 cycles.
      final cycle = cycleDays(run.frequency);
      if (now.difference(run.latest.at).inDays > cycle * 1.5) continue;
      final sub = await _insertSuggestion(
        merchantId: merchantId,
        amountMinor: run.latest.amountMinor,
        frequency: run.frequency,
        source: SubscriptionSource.detected,
        last: run.latest.at,
        next: nextCharge(run.latest.at, run.frequency),
        categoryId: txns.firstWhere((t) => t.id == run.latest.id).categoryId,
      );
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.isIn(run.charges.map((c) => c.id)))).write(
        TransactionsCompanion(
          subscriptionId: Value(sub.id),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<Subscription> _insertSuggestion({
    required String merchantId,
    required int amountMinor,
    required SubscriptionFrequency frequency,
    required SubscriptionSource source,
    DateTime? last,
    DateTime? next,
    String? categoryId,
  }) async {
    final merchant = await (_db.select(
      _db.merchants,
    )..where((m) => m.id.equals(merchantId))).getSingle();
    return _db
        .into(_db.subscriptions)
        .insertReturning(
          SubscriptionsCompanion.insert(
            merchantId: Value(merchantId),
            name: merchant.displayName,
            amountMinor: amountMinor,
            frequency: frequency,
            intervalDays: cycleDays(frequency),
            lastChargedAt: Value(last),
            nextExpectedAt: Value(next),
            status: SubscriptionStatus.suggested,
            source: source,
            categoryId: Value(categoryId),
          ),
        );
  }

  /// Owner adds a plan before any charge is logged (design 04d).
  Future<String> addManual({
    required String name,
    required int amountMinor,
    required SubscriptionFrequency frequency,
    required DateTime next,
    int? reminderDays,
  }) async {
    final row = await _db
        .into(_db.subscriptions)
        .insertReturning(
          SubscriptionsCompanion.insert(
            name: name.trim(),
            amountMinor: amountMinor,
            frequency: frequency,
            intervalDays: cycleDays(frequency),
            nextExpectedAt: Value(next),
            status: SubscriptionStatus.active,
            source: SubscriptionSource.manual,
            reminderDays: Value(reminderDays),
            categoryId: const Value('cat_subscriptions'),
          ),
        );
    await onChanged?.call();
    return row.id;
  }

  /// Owner starts tracking from one payment (history not imported, or a
  /// plan the detector missed). Reuses the merchant's suggestion if any.
  Future<String> trackFromTransaction(
    String txnId,
    SubscriptionFrequency frequency,
    DateTime next,
  ) async {
    final id = await _db.transaction(() async {
      final t = await (_db.select(
        _db.transactions,
      )..where((x) => x.id.equals(txnId))).getSingle();
      final open =
          await (_db.select(_db.subscriptions)..where(
                (s) =>
                    s.deletedAt.isNull() &
                    s.merchantId.equals(t.merchantId!) &
                    s.status.isInValues([
                      SubscriptionStatus.suggested,
                      SubscriptionStatus.active,
                    ]),
              ))
              .getSingleOrNull();
      final values = SubscriptionsCompanion(
        amountMinor: Value(t.amountMinor),
        frequency: Value(frequency),
        intervalDays: Value(cycleDays(frequency)),
        lastChargedAt: Value(t.occurredAt),
        nextExpectedAt: Value(next),
        status: const Value(SubscriptionStatus.active),
        updatedAt: Value(DateTime.now()),
      );
      String subId;
      if (open != null) {
        await (_db.update(
          _db.subscriptions,
        )..where((s) => s.id.equals(open.id))).write(values);
        subId = open.id;
      } else {
        final merchant = await (_db.select(
          _db.merchants,
        )..where((m) => m.id.equals(t.merchantId!))).getSingle();
        subId =
            (await _db
                    .into(_db.subscriptions)
                    .insertReturning(
                      values.copyWith(
                        merchantId: Value(t.merchantId),
                        name: Value(merchant.displayName),
                        source: const Value(SubscriptionSource.manual),
                        categoryId: Value(t.categoryId),
                      ),
                    ))
                .id;
      }
      await (_db.update(
        _db.transactions,
      )..where((x) => x.id.equals(txnId))).write(
        TransactionsCompanion(
          subscriptionId: Value(subId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return subId;
    });
    await onChanged?.call();
    return id;
  }

  // ---------------------------------------------------------------- edits

  /// "Track it": the suggestion becomes a plan.
  Future<void> track(String id) => _set(
    id,
    const SubscriptionsCompanion(status: Value(SubscriptionStatus.active)),
  );

  /// "Not a subscription": never suggested again for this merchant.
  Future<void> dismiss(String id) => _db.transaction(() async {
    await _set(
      id,
      const SubscriptionsCompanion(status: Value(SubscriptionStatus.dismissed)),
    );
    await _unlink(id);
  });

  /// Stop tracking: charges stay linked as history. New charges after this
  /// can be suggested again.
  Future<void> stop(String id) => _set(
    id,
    const SubscriptionsCompanion(status: Value(SubscriptionStatus.cancelled)),
  );

  Future<void> setUnused(String id, bool unused) =>
      _set(id, SubscriptionsCompanion(unused: Value(unused)));

  Future<void> rename(String id, String name) =>
      _set(id, SubscriptionsCompanion(name: Value(name.trim())));

  /// New price; the price-change flag clears (the owner has seen it).
  Future<void> setAmount(String id, int amountMinor) => _set(
    id,
    SubscriptionsCompanion(
      amountMinor: Value(amountMinor),
      priceChanged: const Value(false),
    ),
  );

  Future<void> setFrequency(String id, SubscriptionFrequency f) async {
    final sub = await (_db.select(
      _db.subscriptions,
    )..where((s) => s.id.equals(id))).getSingle();
    final last = sub.lastChargedAt;
    await _set(
      id,
      SubscriptionsCompanion(
        frequency: Value(f),
        intervalDays: Value(cycleDays(f)),
        nextExpectedAt: last == null
            ? const Value.absent()
            : Value(nextCharge(last, f)),
      ),
    );
  }

  Future<void> setNextCharge(String id, DateTime day) =>
      _set(id, SubscriptionsCompanion(nextExpectedAt: Value(day)));

  /// Null → follow the global default.
  Future<void> setReminder(String id, int? days) =>
      _set(id, SubscriptionsCompanion(reminderDays: Value(days)));

  Future<void> setDefaultReminder(int days) async {
    await _settings.set(reminderKey, '$days');
    await onChanged?.call();
  }

  Future<void> setCategory(String id, String categoryId) =>
      _set(id, SubscriptionsCompanion(categoryId: Value(categoryId)));

  Future<void> _set(String id, SubscriptionsCompanion c) async {
    await (_db.update(_db.subscriptions)..where((s) => s.id.equals(id))).write(
      c.copyWith(updatedAt: Value(DateTime.now())),
    );
    await onChanged?.call();
  }

  Future<void> _unlink(String id) async {
    await (_db.update(_db.transactions)
          ..where((t) => t.subscriptionId.equals(id)))
        .write(const TransactionsCompanion(subscriptionId: Value(null)));
    await (_db.update(_db.upcomingCharges)
          ..where((u) => u.subscriptionId.equals(id)))
        .write(const UpcomingChargesCompanion(subscriptionId: Value(null)));
  }
}

/// Lowercase words of 3+ letters/digits, for name ↔ payee matching.
Set<String> nameWords(String s) => {
  for (final m in RegExp('[a-z0-9]{3,}').allMatches(s.toLowerCase())) m[0]!,
};
