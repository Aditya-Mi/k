import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/summary/month_report.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;
  final oct = DateTime(2026, 10);

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ingest = IngestionService(db);
    ledger = LedgerRepository(db, onRulesChanged: ingest.invalidate);
  });
  tearDown(() => db.close());

  Future<String> pay(String payee, int rupees, int day) => ingest.addManual(
    direction: Direction.debit,
    amountMinor: rupees * 100,
    occurredAt: DateTime(2026, 10, day, 12),
    payee: payee,
  );

  Future<List<TxnView>> month() => ledger
      .watchTransactions(TxnFilter(from: oct, to: DateTime(2026, 11)))
      .first;

  Future<String> merchantOf(String txnId) async => (await (db.select(
    db.transactions,
  )..where((t) => t.id.equals(txnId))).getSingle()).merchantId!;

  test('renaming to an existing name makes one payee in Summary', () async {
    final a = await pay('ZEPTONOW', 300, 1);
    await pay('ZEPTONOW', 200, 2);
    final b = await pay('Zepto Marketplace', 500, 3);
    await ledger.renameMerchant(await merchantOf(a), 'Zepto');
    expect(await ledger.renameMerchant(await merchantOf(b), 'zepto'), 1);

    final report = MonthReport.build(oct, await month());
    expect(report.payees, hasLength(1));
    expect(report.payees.single.spentMinor, 100000);
    expect(report.payees.single.count, 3);

    // A new message with the folded payee's key lands on the kept merchant.
    final c = await pay('Zepto Marketplace', 50, 4);
    expect(await merchantOf(c), await merchantOf(a));
  });

  test("merge carries a 'use for all' category rule over", () async {
    final a = await pay('ZEPTONOW', 300, 1);
    final b = await pay('Zepto Marketplace', 500, 3);
    await ledger.setCategory(b, 'cat_groceries', applyToMerchant: true);
    await ledger.renameMerchant(await merchantOf(b), 'Zepto');
    await ledger.renameMerchant(await merchantOf(a), 'Zepto');
    final c = await pay('ZEPTONOW', 40, 5);
    final row = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(c))).getSingle();
    expect(row.categoryId, 'cat_groceries');
  });

  test('v7 backfill merges same-name merchants already renamed', () async {
    final a = await pay('ZEPTONOW', 300, 1);
    final b = await pay('Zepto Marketplace', 500, 3);
    for (final id in [await merchantOf(a), await merchantOf(b)]) {
      await (db.update(db.merchants)..where((m) => m.id.equals(id))).write(
        const MerchantsCompanion(displayName: Value('Zepto')),
      );
    }
    await db.mergeSameNameMerchants();
    expect(await merchantOf(a), await merchantOf(b));
  });
}
