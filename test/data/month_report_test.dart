import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' show Category;
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/summary/month_report.dart';
import 'package:k/ui/theme/bands.dart';
import 'package:txn_parser/txn_parser.dart';

Category cat(String id, {String? parent}) => Category(
  id: id,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  name: id,
  icon: 'label',
  color: 0,
  isSystem: true,
  sortOrder: 0,
  hidden: false,
  parentId: parent,
);

var _n = 0;
TxnView txn(
  int rupees,
  DateTime at, {
  String payee = 'Swiggy',
  Category? category,
  bool credit = false,
  String? transferId,
  List<SplitPart> splits = const [],
}) => TxnView(
  id: '${_n++}',
  amountMinor: rupees * 100,
  currency: 'INR',
  direction: credit ? Direction.credit : Direction.debit,
  txnType: TxnType.upi,
  occurredAt: at,
  payee: payee,
  sourceCount: 1,
  category: category,
  transferId: transferId,
  splits: splits,
);

void main() {
  final oct = DateTime(2026, 10);
  final food = cat('cat_food');
  final travel = cat('cat_travel');

  test('month report: days, categories, payees, bands, trend', () {
    final r = MonthReport.build(oct, [
      txn(250, DateTime(2026, 10, 1, 9), category: food),
      txn(150, DateTime(2026, 10, 1, 20), category: food),
      txn(9240, DateTime(2026, 10, 11), payee: 'IRCTC', category: travel),
      txn(5000, DateTime(2026, 10, 3), payee: 'Self', transferId: 't1'),
      txn(80000, DateTime(2026, 10, 2), payee: 'Salary', credit: true),
      txn(1000, DateTime(2026, 9, 15)),
      txn(700, DateTime(2026, 5, 2)),
      txn(999, DateTime(2026, 4, 30)), // before the trend window
    ]);

    expect(r.spentMinor, 964000);
    expect(r.inMinor, 8000000);
    expect(r.spends, 3);
    expect(r.dayTotals, hasLength(31));
    expect(r.dayTotals[0], 40000);
    expect(r.dayTotals[2], 0, reason: 'self transfer is not spend');
    expect(r.biggestDay, (11, 924000));

    expect(r.categories.map((c) => c.category?.id), ['cat_travel', 'cat_food']);
    expect(r.categories.last.count, 2);

    expect(r.payees.first.payee, 'IRCTC');
    expect(r.payees[1].payee, 'Swiggy');
    expect(r.payees[1].count, 2);
    expect(r.payees[1].category?.id, 'cat_food');
    expect(r.payeeCount, 2);

    expect(r.bandCounts[Bands.of(25000)], 1);
    expect(r.bandCounts[Bands.of(15000)], 1);
    expect(r.bandTotals[Bands.of(924000)], 924000);

    expect(r.trend.map((m) => m.month.month), [5, 6, 7, 8, 9, 10]);
    expect(r.trend.map((m) => m.spentMinor), [70000, 0, 0, 0, 100000, 964000]);
    expect(r.trendAverage, 85000);
  });

  test('empty month', () {
    final r = MonthReport.build(DateTime(2026, 2), const []);
    expect(r.dayTotals, hasLength(28));
    expect(r.biggestDay, isNull);
    expect(r.trendAverage, isNull);
    expect(r.categories, isEmpty);
  });

  test('split parts count in their own category; sub-categories add up '
      'under the parent', () {
    final groceries = cat('cat_groceries');
    final habits = cat('c_habits');
    final cigs = cat('c_cigs', parent: 'c_habits');
    final drinks = cat('c_drinks', parent: 'c_habits');
    final r = MonthReport.build(
      oct,
      [
        txn(
          1240,
          DateTime(2026, 10, 4),
          payee: 'Zepto',
          category: groceries,
          splits: [SplitPart(id: 's1', category: cigs, amountMinor: 30000)],
        ),
        txn(500, DateTime(2026, 10, 5), payee: 'Bar', category: drinks),
        txn(100, DateTime(2026, 10, 6), payee: 'Shop', category: habits),
      ],
      categories: {
        for (final c in [groceries, habits, cigs, drinks]) c.id: c,
      },
    );
    expect(r.spentMinor, 184000, reason: 'a split payment counts once');
    expect(r.categories.map((c) => (c.category?.id, c.spentMinor)), [
      ('cat_groceries', 94000),
      ('c_habits', 90000),
    ]);
    final h = r.categories.last;
    expect(h.children.map((c) => (c.category?.id, c.spentMinor)), [
      ('c_drinks', 50000),
      ('c_cigs', 30000),
      ('c_habits', 10000),
    ]);
    expect(r.categories.first.children, isEmpty);
  });
}
