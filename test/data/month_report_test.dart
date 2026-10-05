import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' show Category;
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/summary/month_report.dart';
import 'package:k/ui/theme/bands.dart';
import 'package:txn_parser/txn_parser.dart';

Category cat(String id) => Category(
  id: id,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  name: id,
  icon: 'label',
  color: 0,
  isSystem: true,
  sortOrder: 0,
  hidden: false,
);

var _n = 0;
TxnView txn(
  int rupees,
  DateTime at, {
  String payee = 'Swiggy',
  Category? category,
  bool credit = false,
  String? transferId,
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
}
