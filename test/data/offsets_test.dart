import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart';
import 'package:k/data/db/enums.dart';
import 'package:k/data/ingest/category_resolver.dart';
import 'package:k/data/ingest/offset_linker.dart';
import 'package:k/data/summary/month_report.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/repositories/offsets.dart';
import 'package:k/ui/screens/transactions/transactions_cubit.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  group('allocateOffsets', () {
    OffsetRow row(String id, Direction d, int amount, int day) => (
      id: id,
      offsetId: 'g',
      direction: d,
      amountMinor: amount,
      occurredAt: DateTime(2026, 10, day),
    );

    test('friends paying back part of a dinner', () {
      final s = allocateOffsets([
        row('dinner', Direction.debit, 3000, 1),
        row('a', Direction.credit, 750, 2),
        row('b', Direction.credit, 750, 2),
        row('c', Direction.credit, 750, 3),
      ]);
      expect(s['dinner']!.cancelledMinor, 2250);
      expect(s['dinner']!.others, 3);
      for (final id in ['a', 'b', 'c']) {
        expect(s[id]!.cancelledMinor, 750);
      }
    });

    test('money passed on: the larger side keeps the rest, oldest first', () {
      final s = allocateOffsets([
        row('mom', Direction.credit, 10000, 1),
        row('out1', Direction.debit, 5000, 2),
        row('out2', Direction.debit, 3000, 3),
      ]);
      expect(s['mom']!.cancelledMinor, 8000);
      expect(s['out1']!.cancelledMinor, 5000);
      expect(s['out2']!.cancelledMinor, 3000);
    });

    test('a payment left alone counts as usual', () {
      expect(allocateOffsets([row('x', Direction.debit, 500, 1)]), isEmpty);
    });
  });

  group('kinds and offsets in totals', () {
    Category cat(String id, CategoryKind kind) => Category(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      name: id,
      icon: 'label',
      color: 0,
      isSystem: false,
      sortOrder: 0,
      hidden: false,
      kind: kind,
    );
    final food = cat('cat_food', CategoryKind.spend);
    final invest = cat('cat_investments', CategoryKind.neutral);
    final income = cat('cat_income', CategoryKind.income);
    final uncategorized = cat('cat_uncategorized', CategoryKind.spend);
    var n = 0;
    TxnView txn(int amount, {Category? category, bool credit = false}) =>
        TxnView(
          id: '${n++}',
          amountMinor: amount,
          currency: 'INR',
          direction: credit ? Direction.credit : Direction.debit,
          txnType: TxnType.upi,
          occurredAt: DateTime(2026, 10, 5),
          payee: 'x',
          sourceCount: 1,
          category: category,
        );

    test('money back in a spending category lowers spent', () {
      final s = summarize(DateTime(2026, 10), [
        txn(2000, category: food),
        txn(500, category: food, credit: true),
      ]);
      expect(s.spentMinor, 1500);
      expect(s.inMinor, 0);
    });

    test('uncategorized and income credits came in', () {
      final s = summarize(DateTime(2026, 10), [
        txn(700, category: uncategorized, credit: true),
        txn(50000, category: income, credit: true),
        txn(300, credit: true),
      ]);
      expect(s.inMinor, 51000);
      expect(s.spentMinor, 0);
    });

    test('neither: investments count nowhere', () {
      final s = summarize(DateTime(2026, 10), [
        txn(5000, category: invest),
        txn(6000, category: invest, credit: true),
      ]);
      expect(s.spentMinor, 0);
      expect(s.inMinor, 0);
    });

    test('only what is left after cancelling counts', () {
      final dinner = txn(
        3000,
        category: food,
      ).withOffset((offsetId: 'g', cancelledMinor: 2250, others: 3));
      final back = txn(
        750,
        credit: true,
        category: food,
      ).withOffset((offsetId: 'g', cancelledMinor: 750, others: 3));
      expect(back.cancelsOut, isTrue);
      final s = summarize(DateTime(2026, 10), [dinner, back]);
      expect(s.spentMinor, 750);
      expect(s.inMinor, 0);
    });

    test('a neutral split part drops out of spent', () {
      final t = txn(
        1000,
        category: food,
      ).withSplits([SplitPart(id: 's', category: invest, amountMinor: 400)]);
      expect(t.spentMinor, 600);
    });
  });

  group('OffsetLinker + repository', () {
    late AppDatabase db;
    late OffsetLinker linker;
    late LedgerRepository ledger;
    final oct = TxnFilter.month(DateTime(2026, 10));

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      linker = OffsetLinker(db);
      ledger = LedgerRepository(db);
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: const Value('acc'),
              bankId: 'AXIS',
              type: AccountType.savings,
              last4: const Value('1111'),
            ),
          );
    });
    tearDown(() => db.close());

    Future<String> add(
      int rupees,
      Direction d,
      DateTime at, {
      String? ref,
      String category = 'cat_uncategorized',
    }) async =>
        (await db
                .into(db.transactions)
                .insertReturning(
                  TransactionsCompanion.insert(
                    accountId: const Value('acc'),
                    amountMinor: rupees * 100,
                    direction: d,
                    txnType: TxnType.upi,
                    occurredAt: at,
                    refNo: Value(ref),
                    categoryId: Value(category),
                  ),
                ))
            .id;

    test('a failed UPI payment and its reversal cancel out', () async {
      final debit = await add(
        499,
        Direction.debit,
        DateTime(2026, 10, 3, 10),
        category: 'cat_food',
      );
      final credit = await add(
        499,
        Direction.credit,
        DateTime(2026, 10, 3, 11),
      );
      expect(
        await linker.autoReversal(
          credit,
          text: 'Rs 499.00 credited to A/c XX1111, reversal of failed UPI txn',
        ),
        isTrue,
      );
      final rows = await ledger.watchTransactions(oct).first;
      expect(rows.every((r) => r.cancelsOut), isTrue);
      expect(summarize(DateTime(2026, 10), rows).spentMinor, 0);
      expect(summarize(DateTime(2026, 10), rows).inMinor, 0);
      expect(rows.firstWhere((r) => r.id == debit).offsetOthers, 1);
    });

    test('same reference links without reversal words', () async {
      await add(
        200,
        Direction.debit,
        DateTime(2026, 10, 3),
        ref: '612345678901',
      );
      final c = await add(
        200,
        Direction.credit,
        DateTime(2026, 10, 4),
        ref: '612345678901',
      );
      expect(await linker.autoReversal(c, text: 'Rs 200 credited'), isTrue);
    });

    test('an ordinary credit of the same amount is left alone', () async {
      await add(200, Direction.debit, DateTime(2026, 10, 3));
      final c = await add(200, Direction.credit, DateTime(2026, 10, 4));
      expect(
        await linker.autoReversal(c, text: 'Rs 200 received from RAHUL'),
        isFalse,
      );
    });

    test('unlinking ends a pair and stops auto-linking it again', () async {
      final d = await add(499, Direction.debit, DateTime(2026, 10, 3));
      final c = await add(499, Direction.credit, DateTime(2026, 10, 3, 1));
      await linker.link(d, c);
      await linker.unlink(c);
      final rows = await db.select(db.transactions).get();
      expect(rows.every((r) => r.offsetId == null), isTrue);
      expect(rows.every((r) => r.autoOffsetOff), isTrue);
      expect(await linker.autoReversal(c, text: 'reversal'), isFalse);
    });

    test('linking into a group joins it; leaving keeps the rest', () async {
      final dinner = await add(3000, Direction.debit, DateTime(2026, 10, 1));
      final a = await add(750, Direction.credit, DateTime(2026, 10, 2));
      final b = await add(750, Direction.credit, DateTime(2026, 10, 2, 1));
      await linker.link(dinner, a);
      await linker.link(b, dinner);
      var rows = await ledger.watchTransactions(oct).first;
      expect(rows.firstWhere((r) => r.id == dinner).countedMinor, 150000);
      await linker.unlink(b);
      rows = await ledger.watchTransactions(oct).first;
      expect(rows.firstWhere((r) => r.id == dinner).countedMinor, 225000);
      expect(rows.firstWhere((r) => r.id == b).hasOffset, isFalse);
    });

    test('a sub-category takes its parent kind; kind passes down', () async {
      final parent = await ledger.addCategory('Family', 'label');
      final child = await ledger.addCategory(
        'Mom',
        'label',
        parentId: parent.id,
        kind: CategoryKind.income,
      );
      expect(child.kind, CategoryKind.spend);
      await ledger.updateCategory(parent.id, kind: CategoryKind.neutral);
      final all = await ledger.watchCategories().first;
      expect(
        all.firstWhere((c) => c.id == child.id).kind,
        CategoryKind.neutral,
      );
      expect(
        all.firstWhere((c) => c.id == 'cat_investments').kind,
        CategoryKind.neutral,
      );
    });
  });

  group('pass-through suggestions', () {
    PassRow r(String id, Direction d, int amount, int day, [int hour = 9]) => (
      id: id,
      direction: d,
      amountMinor: amount,
      occurredAt: DateTime(2026, 10, day, hour),
    );

    test('money in then most of it out soon after pairs up', () {
      final pairs = suggestPassThroughs([
        r('mom', Direction.credit, 10000, 1),
        r('rent', Direction.debit, 8000, 2),
        r('coffee', Direction.debit, 200, 1, 10),
      ]);
      expect(pairs, [('mom', 'rent')]);
    });

    test('too small, too late, or before the money came: no pair', () {
      expect(
        suggestPassThroughs([
          r('salary', Direction.credit, 45000, 1),
          r('rent', Direction.debit, 15000, 2),
          r('late', Direction.debit, 45000, 6),
          r('before', Direction.debit, 45000, 1, 8),
        ]),
        isEmpty,
      );
    });

    test('each payment pairs once, closest first', () {
      final pairs = suggestPassThroughs([
        r('a', Direction.credit, 5000, 1),
        r('b', Direction.credit, 5000, 1, 10),
        r('x', Direction.debit, 5000, 1, 11),
      ]);
      expect(pairs, [('a', 'x')]);
    });
  });

  test('Summary: neither and cancelled-out money are listed apart', () {
    Category cat(String id, CategoryKind kind) => Category(
      id: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      name: id,
      icon: 'label',
      color: 0,
      isSystem: false,
      sortOrder: 0,
      hidden: false,
      kind: kind,
    );
    final invest = cat('cat_investments', CategoryKind.neutral);
    final food = cat('cat_food', CategoryKind.spend);
    TxnView t(String id, int amount, Category c, {int cancelled = 0}) =>
        TxnView(
          id: id,
          amountMinor: amount,
          currency: 'INR',
          direction: Direction.debit,
          txnType: TxnType.upi,
          occurredAt: DateTime(2026, 10, 5),
          payee: id,
          sourceCount: 1,
          category: c,
        ).withOffset(
          cancelled == 0
              ? null
              : (offsetId: 'g', cancelledMinor: cancelled, others: 1),
        );
    final r = MonthReport.build(DateTime(2026, 10), [
      t('sip', 5000, invest),
      t('sip2', 2000, invest),
      t('dinner', 3000, food, cancelled: 2250),
    ]);
    expect(r.spentMinor, 750);
    expect(r.notCounted.single.category?.id, 'cat_investments');
    expect(r.notCounted.single.spentMinor, 7000);
    expect(r.cancelledMinor, 2250);
  });

  test('a payee\'s spending rule is not applied to money from them', () {
    CategoryRule rule(String pattern, String cat) => CategoryRule(
      id: 'mr_$pattern',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      matchType: RuleMatchType.merchant,
      pattern: pattern,
      categoryId: cat,
      priority: 100,
      origin: RuleOrigin.user,
    );
    final resolver = CategoryResolver(
      [rule('rahul', 'cat_bills'), rule('zerodha', 'cat_investments')],
      spendIds: {'cat_bills'},
    );
    expect(resolver.resolve(merchantKey: 'rahul'), 'cat_bills');
    expect(
      resolver.resolve(merchantKey: 'rahul', credit: true),
      'cat_uncategorized',
    );
    expect(
      resolver.resolve(merchantKey: 'zerodha', credit: true),
      'cat_investments',
    );
  });
}
