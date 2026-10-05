import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;

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

  Future<Transaction> pay(String payee) async {
    final id = await ingest.addManual(
      direction: Direction.debit,
      amountMinor: 1100000,
      occurredAt: DateTime(2026, 10, 1),
      payee: payee,
    );
    return (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  test('own category: added last, pickable, used by "use for all"', () async {
    final rent = await ledger.addCategory('Rent', 'home');
    final picks = await ledger.watchCategories().first;
    expect(picks.last.id, rent.id);
    expect(rent.isSystem, isFalse);

    final first = await pay('Mr Sharma');
    await ledger.setCategory(first.id, rent.id, applyToMerchant: true);
    expect((await pay('Mr Sharma')).categoryId, rent.id);

    final use = await ledger.watchCategoryUse().first;
    expect(use.firstWhere((e) => e.$1.id == rent.id).$2, 2);
  });

  test('hidden: not offered, rules skip it, past payments keep it', () async {
    final rent = await ledger.addCategory('Rent', 'home');
    final first = await pay('Mr Sharma');
    await ledger.setCategory(first.id, rent.id, applyToMerchant: true);

    await ledger.setCategoryHidden(rent.id, true);
    expect(
      (await ledger.watchCategories().first).map((c) => c.id),
      isNot(contains(rent.id)),
    );
    expect(
      (await ledger.watchCategories(includeHidden: true).first).map(
        (c) => c.id,
      ),
      contains(rent.id),
    );
    expect((await pay('Mr Sharma')).categoryId, isNot(rent.id));
    final past = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(first.id))).getSingle();
    expect(past.categoryId, rent.id);
  });
}
