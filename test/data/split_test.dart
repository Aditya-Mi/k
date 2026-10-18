import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
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

  Future<String> pay(String payee, int rupees) => ingest.addManual(
    direction: Direction.debit,
    amountMinor: rupees * 100,
    occurredAt: DateTime(2026, 10, 4, 12),
    payee: payee,
  );

  Future<List<TxnView>> month([Set<String> cats = const {}]) => ledger
      .watchTransactions(
        TxnFilter(from: oct, to: DateTime(2026, 11), categoryIds: cats),
      )
      .first;

  test('a split keeps the rest in the payment category; filters find the '
      'parts and a parent takes in its sub-categories', () async {
    final habits = await ledger.addCategory('Habits', 'self_improvement');
    final cigs = await ledger.addCategory(
      'Cigarettes',
      'smoking_rooms',
      parentId: habits.id,
    );
    final order = await pay('Zepto', 1240);
    await ledger.setCategory(order, 'cat_groceries');
    await pay('Swiggy', 300);

    await ledger.setSplits(order, [
      (categoryId: cigs.id, amountMinor: 30000),
    ]);
    final v = (await month()).firstWhere((t) => t.id == order);
    expect(v.restMinor, 94000);
    expect(v.pieces.map((p) => (p.$1?.id, p.$2)), [
      ('cat_groceries', 94000),
      (cigs.id, 30000),
    ]);

    expect((await month({cigs.id})).map((t) => t.id), [order]);
    expect((await month({habits.id})).map((t) => t.id), [order]);
    expect((await month({'cat_groceries'})).map((t) => t.id), [order]);

    // Saving again replaces the parts; none removes the split.
    await ledger.setSplits(order, []);
    expect((await month()).firstWhere((t) => t.id == order).isSplit, false);
    expect(await month({habits.id}), isEmpty);
  });
}
