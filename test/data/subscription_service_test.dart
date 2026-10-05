import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/db/enums.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/repositories/settings_repository.dart';
import 'package:k/data/subscriptions/subscription_service.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  late AppDatabase db;
  late SubscriptionService subs;
  late String account;
  final now = DateTime(2026, 10, 4, 12);

  Future<String> merchant(String name) async =>
      (await db
              .into(db.merchants)
              .insertReturning(
                MerchantsCompanion.insert(
                  normalizedKey: name.toLowerCase(),
                  displayName: name,
                ),
              ))
          .id;

  Future<String> debit(String merchantId, int rupees, DateTime at) async =>
      (await db
              .into(db.transactions)
              .insertReturning(
                TransactionsCompanion.insert(
                  accountId: Value(account),
                  amountMinor: rupees * 100,
                  direction: Direction.debit,
                  txnType: TxnType.upi,
                  merchantId: Value(merchantId),
                  occurredAt: at,
                ),
              ))
          .id;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final ledger = LedgerRepository(db);
    subs = SubscriptionService(db, ledger, SettingsRepository(db));
    account =
        (await db
                .into(db.accounts)
                .insertReturning(
                  AccountsCompanion.insert(
                    bankId: 'KOTAK',
                    type: AccountType.savings,
                    last4: const Value('5555'),
                  ),
                ))
            .id;
  });
  tearDown(() => db.close());

  test('repeat charges → suggestion → tracked → price change', () async {
    final spotify = await merchant('Spotify');
    for (final m in [8, 9, 10]) {
      await debit(spotify, 119, DateTime(2026, m, 2, 9));
    }
    await subs.refresh(now: now);
    var o = await subs.watch().first;
    expect(o.suggestions, hasLength(1));
    final s = o.suggestions.single;
    expect(s.name, 'Spotify');
    expect(s.row.frequency, SubscriptionFrequency.monthly);
    expect(s.chargeDates, hasLength(3));
    expect(s.account?.last4, '5555');
    expect(s.row.nextExpectedAt, DateTime(2026, 11, 2, 9));

    await subs.track(s.id);
    o = await subs.watch().first;
    expect(o.active.single.id, s.id);
    expect(o.perMonthMinor, 11900);

    // Charged on time at a new price.
    await debit(spotify, 139, DateTime(2026, 11, 3, 9));
    await subs.refresh(now: DateTime(2026, 11, 3, 12));
    final v = (await subs.watchOne(s.id).first)!;
    expect(v.amountMinor, 13900);
    expect(v.previousAmountMinor, 11900);
    expect(v.priceUp, isTrue);
    expect(v.chargeDates, hasLength(4));
    expect(v.row.nextExpectedAt, DateTime(2026, 12, 3, 9));

    // Next charge at the same price clears the flag.
    await debit(spotify, 139, DateTime(2026, 12, 3, 9));
    await subs.refresh(now: DateTime(2026, 12, 3, 12));
    expect((await subs.watchOne(s.id).first)!.priceUp, isFalse);
  });

  test('dismissed suggestions do not come back', () async {
    final gym = await merchant('Corner Gym');
    for (final m in [8, 9, 10]) {
      await debit(gym, 1500, DateTime(2026, m, 1));
    }
    await subs.refresh(now: now);
    final s = (await subs.watch().first).suggestions.single;
    await subs.dismiss(s.id);
    await subs.refresh(now: now);
    expect((await subs.watch().first).suggestions, isEmpty);
    final linked = await (db.select(
      db.transactions,
    )..where((t) => t.subscriptionId.isNotNull())).get();
    expect(linked, isEmpty);
  });

  test('everyday spends are not suggested', () async {
    final zepto = await merchant('Zepto');
    for (var d = 1; d < 90; d += 3) {
      await debit(zepto, 250, DateTime(2026, 7, d));
    }
    await subs.refresh(now: now);
    expect((await subs.watch().first).suggestions, isEmpty);
  });

  test('AutoPay alert suggests, sets the date, and settles on debit', () async {
    final netflix = await merchant('Netflix');
    final alert = await db
        .into(db.upcomingCharges)
        .insertReturning(
          UpcomingChargesCompanion.insert(
            merchantId: Value(netflix),
            amountMinor: 64900,
            dueDate: DateTime(2026, 10, 8),
            status: UpcomingChargeStatus.pending,
          ),
        );
    await subs.refresh(now: now);
    final s = (await subs.watch().first).suggestions.single;
    expect(s.autoPay, isTrue);
    expect(s.row.nextExpectedAt, DateTime(2026, 10, 8));
    await subs.track(s.id);

    final paid = await debit(netflix, 649, DateTime(2026, 10, 8, 6));
    await subs.refresh(now: DateTime(2026, 10, 8, 12));
    final u = await (db.select(
      db.upcomingCharges,
    )..where((x) => x.id.equals(alert.id))).getSingle();
    expect(u.status, UpcomingChargeStatus.matched);
    expect(u.matchedTransactionId, paid);
    final v = (await subs.watchOne(s.id).first)!;
    expect(v.row.nextExpectedAt, DateTime(2026, 11, 8, 6));
    expect(v.priceUp, isFalse);
  });

  test('track from one payment, then the next charge matches', () async {
    final apple = await merchant('Apple Media Services');
    final first = await debit(apple, 195, DateTime(2026, 9, 29, 6));
    final id = await subs.trackFromTransaction(
      first,
      SubscriptionFrequency.monthly,
      DateTime(2026, 10, 29),
    );
    var v = (await subs.watchOne(id).first)!;
    expect(v.row.status, SubscriptionStatus.active);
    expect(v.row.source, SubscriptionSource.manual);
    expect(v.chargeDates, [DateTime(2026, 9, 29, 6)]);

    await debit(apple, 195, DateTime(2026, 10, 29, 6));
    await subs.refresh(now: DateTime(2026, 10, 29, 12));
    v = (await subs.watchOne(id).first)!;
    expect(v.chargeDates, hasLength(2));
    expect(v.row.nextExpectedAt, DateTime(2026, 11, 29, 6));
    // No duplicate suggestion for the same merchant.
    expect((await subs.watch().first).suggestions, isEmpty);
  });

  test('manual plan links its first charge by name, amount and date', () async {
    final id = await subs.addManual(
      name: 'Apple Music',
      amountMinor: 19500,
      frequency: SubscriptionFrequency.monthly,
      next: DateTime(2026, 10, 23),
    );
    final apple = await merchant('Apple Media Services');
    final other = await merchant('Apple Store');
    await debit(other, 79900, DateTime(2026, 10, 22)); // wrong amount
    final paid = await debit(apple, 195, DateTime(2026, 10, 23, 6));
    await subs.refresh(now: DateTime(2026, 10, 23, 12));
    final v = (await subs.watchOne(id).first)!;
    expect(v.row.merchantId, apple);
    expect(v.chargeDates, [DateTime(2026, 10, 23, 6)]);
    expect(v.row.nextExpectedAt, DateTime(2026, 11, 23, 6));
    final t = await (db.select(
      db.transactions,
    )..where((x) => x.id.equals(paid))).getSingle();
    expect(t.subscriptionId, id);

    // November follows the payee like any tracked plan.
    await debit(apple, 195, DateTime(2026, 11, 23, 6));
    await subs.refresh(now: DateTime(2026, 11, 23, 12));
    expect((await subs.watchOne(id).first)!.chargeDates, hasLength(2));
  });

  test('stopped plans can be suggested again from new charges', () async {
    final m = await merchant('Hotstar');
    for (final mo in [5, 6, 7]) {
      await debit(m, 299, DateTime(2026, mo, 10));
    }
    await subs.refresh(now: DateTime(2026, 7, 11));
    final s = (await subs.watch().first).suggestions.single;
    await subs.track(s.id);
    await subs.stop(s.id);
    expect((await subs.watch().first).active, isEmpty);
    for (final mo in [8, 9, 10]) {
      await debit(m, 299, DateTime(2026, mo, 10));
    }
    await subs.refresh(now: DateTime(2026, 10, 11));
    expect((await subs.watch().first).suggestions, hasLength(1));
  });
}
