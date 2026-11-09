// QA audit: balances, splits, merges, restore, dates and startup safety.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/core/security/db_key_manager.dart';
import 'package:k/data/backup/snapshot.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/db/enums.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/subscriptions/recurrence.dart';
import 'package:k/ui/screens/transactions/transactions_cubit.dart';
import 'package:txn_parser/txn_parser.dart';

AppDatabase memoryDb() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;
  final oct = TxnFilter.month(DateTime(2026, 10));

  setUp(() {
    db = memoryDb();
    ingest = IngestionService(db);
    ledger = LedgerRepository(db, onRulesChanged: ingest.invalidate);
  });
  tearDown(() => db.close());

  Future<String> savings(String last4) async =>
      (await db
              .into(db.accounts)
              .insertReturning(
                AccountsCompanion.insert(
                  bankId: 'AXIS',
                  type: AccountType.savings,
                  last4: Value(last4),
                ),
              ))
          .id;

  test(
    'lowering a split payment\'s amount never counts more than it',
    () async {
      final id = await ingest.addManual(
        direction: Direction.debit,
        amountMinor: 124000,
        occurredAt: DateTime(2026, 10, 3, 12),
        categoryId: 'cat_food',
      );
      await ledger.setSplits(id, [
        (categoryId: 'cat_shopping', amountMinor: 30000),
      ]);
      // Owner fixes a typo: it was ₹200, not ₹1,240.
      await ingest.editTransaction(
        id,
        direction: Direction.debit,
        amountMinor: 20000,
        occurredAt: DateTime(2026, 10, 3, 12),
        accountId: null,
        txnType: TxnType.other,
        categoryId: null,
        note: '',
      );
      final rows = await ledger.watchTransactions(oct).first;
      expect(summarize(oct.from, rows).spentMinor, 20000);
    },
  );

  test(
    'balance does not depend on row order when two alerts share a minute',
    () async {
      final acc = await savings('1111');
      final at = DateTime(2026, 10, 3, 12, 0);
      Future<Transaction> txn(int amount, int balance) => db
          .into(db.transactions)
          .insertReturning(
            TransactionsCompanion.insert(
              accountId: Value(acc),
              amountMinor: amount,
              direction: Direction.debit,
              txnType: TxnType.upi,
              occurredAt: at,
              balanceMinor: Value(balance),
            ),
          );
      // Arrival order: ₹500 out leaves ₹1,000; then ₹200 out leaves ₹800.
      final first = await txn(50000, 100000);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await txn(20000, 80000);
      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(acc))).getSingle();
      final ab = computeBalance(account, [first, second])!.amountMinor;
      final ba = computeBalance(account, [second, first])!.amountMinor;
      expect(ab, ba);
      expect(ab, 80000);
    },
  );

  test(
    'a SMS whose amount overflows goes to Review instead of throwing',
    () async {
      final outcome = await ingest.ingest(
        IncomingMessage(
          channel: Channel.sms,
          sender: 'AX-AXISBK-S',
          body:
              'INR 99999999999999999999.00 debited\nA/c no. XX1111\n'
              '03-10-26, 17:04:51\nUPI/P2M/100000000011/TEST SHOP\n'
              'Not you? SMS BLOCKUPI Cust ID to 910000000000\nAxis Bank',
          receivedAt: DateTime(2026, 10, 3, 17, 4, 51),
        ),
      );
      expect(outcome, IngestOutcome.needsReview);
      expect(await db.select(db.transactions).get(), isEmpty);
    },
  );

  group('account merge', () {
    Future<List<String>> shown() async => [
      for (final a in await ledger.watchAccounts().first) a.id,
    ];

    test('into itself keeps the account', () async {
      final a = await savings('1111');
      await ledger.mergeAccount(a, a);
      expect(await shown(), contains(a));
    });

    test('back the other way never hides both', () async {
      final a = await savings('1111');
      final b = await savings('2222');
      await ledger.mergeAccount(a, b);
      await ledger.mergeAccount(b, a);
      final ids = await shown();
      expect(ids.contains(a) || ids.contains(b), isTrue);
    });

    test('moves the account\'s EMIs too', () async {
      final a = await savings('1111');
      final b = await savings('2222');
      await db
          .into(db.emis)
          .insert(
            EmisCompanion.insert(
              name: 'Loan',
              kind: EmiKind.values.first,
              accountId: Value(a),
              amountMinor: 500000,
              count: 12,
              firstDueAt: DateTime(2026, 10, 5),
              status: EmiStatus.values.first,
            ),
          );
      await ledger.mergeAccount(a, b);
      expect((await db.select(db.emis).getSingle()).accountId, b);
    });
  });

  test('restoring a v10 backup gives income its kind', () async {
    final (snap, _) = await Snapshot(db).take();
    snap['schema'] = 10;
    final tables = snap['tables'] as Map<String, dynamic>;
    for (final r in tables['categories'] as List<dynamic>) {
      (r as Map<String, dynamic>).remove('kind');
    }
    final b = memoryDb();
    addTearDown(b.close);
    await Snapshot(b).restore(snap);
    final income = await (b.select(
      b.categories,
    )..where((c) => c.id.equals('cat_income'))).getSingle();
    expect(income.kind, CategoryKind.income);
  });

  test('tracking a 31st-of-month charge months later keeps the 31st', () {
    final next = nextChargeAfter(
      DateTime(2026, 1, 31, 10),
      SubscriptionFrequency.monthly,
      today: DateTime(2026, 3, 15),
    );
    expect(next, DateTime(2026, 3, 31, 10));
  });

  test(
    'a lost DB key with a database on disk is an error, never a new key',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      final keys = DbKeyManager(storage, databaseExists: () async => true);
      await expectLater(keys.getOrCreateKey(), throwsA(isA<DbKeyLostError>()));
      expect(await storage.read(key: 'db_key_v1'), isNull);
    },
  );
}
