import 'package:equatable/equatable.dart';

import '../db/app_database.dart' show Category;
import '../repositories/ledger_models.dart';
import '../../ui/theme/bands.dart';

/// Spend for one month in the trend.
class MonthSpend extends Equatable {
  const MonthSpend(this.month, this.spentMinor);

  final DateTime month;
  final int spentMinor;

  @override
  List<Object?> get props => [month, spentMinor];
}

class CategorySpend extends Equatable {
  const CategorySpend(this.category, this.spentMinor, this.count);

  /// Null = uncategorized.
  final Category? category;
  final int spentMinor;
  final int count;

  @override
  List<Object?> get props => [category?.id, spentMinor, count];
}

class PayeeSpend extends Equatable {
  const PayeeSpend(this.payee, this.spentMinor, this.count, this.category);

  final String payee;
  final int spentMinor;
  final int count;

  /// The category most of their payments carry.
  final Category? category;

  @override
  List<Object?> get props => [payee, spentMinor, count, category?.id];
}

/// Everything the Summary tab draws for one month (design 05). Spend means
/// debits that aren't self transfers, as on the month panel.
class MonthReport extends Equatable {
  const MonthReport({
    required this.month,
    required this.trend,
    required this.dayTotals,
    required this.categories,
    required this.payees,
    required this.payeeCount,
    required this.bandTotals,
    required this.bandCounts,
    required this.spentMinor,
    required this.inMinor,
    required this.spends,
  });

  final DateTime month;

  /// Six months ending with [month], oldest first.
  final List<MonthSpend> trend;

  /// Spend per day of [month] (index 0 = the 1st).
  final List<int> dayTotals;

  /// Biggest first.
  final List<CategorySpend> categories;

  /// Top payees, biggest first (at most [topPayees]).
  final List<PayeeSpend> payees;
  final int payeeCount;

  /// Spend and number of spends per band (Bands index).
  final List<int> bandTotals;
  final List<int> bandCounts;

  final int spentMinor;
  final int inMinor;
  final int spends;

  static const topPayees = 5;
  static const trendMonths = 6;

  /// Average of the complete months in the trend that had any spend.
  int? get trendAverage {
    final past = [
      for (final m in trend.take(trend.length - 1))
        if (m.spentMinor > 0) m.spentMinor,
    ];
    if (past.isEmpty) return null;
    return past.reduce((a, b) => a + b) ~/ past.length;
  }

  /// (day, amount) of the biggest day, or null.
  (int, int)? get biggestDay {
    var best = -1;
    for (var i = 0; i < dayTotals.length; i++) {
      if (dayTotals[i] > 0 && (best < 0 || dayTotals[i] > dayTotals[best])) {
        best = i;
      }
    }
    return best < 0 ? null : (best + 1, dayTotals[best]);
  }

  @override
  List<Object?> get props => [
    month, trend, dayTotals, categories, payees, payeeCount, bandTotals, //
    bandCounts, spentMinor, inMinor, spends,
  ];

  /// [txns] covers the six trend months (any order).
  static MonthReport build(DateTime month, List<TxnView> txns) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final days = end.difference(start).inDays;

    final perMonth = <DateTime, int>{
      for (var i = trendMonths - 1; i >= 0; i--)
        DateTime(month.year, month.month - i): 0,
    };
    final dayTotals = List.filled(days, 0);
    final cats = <String?, (Category?, int, int)>{};
    final payees =
        <String, (String, int, int, Map<String?, (Category?, int)>)>{};
    final bandTotals = List.filled(Bands.count, 0);
    final bandCounts = List.filled(Bands.count, 0);
    var spent = 0, came = 0, spends = 0;

    for (final t in txns) {
      if (!t.countsInTotals) continue;
      final at = t.occurredAt;
      final key = DateTime(at.year, at.month);
      final inMonth = !at.isBefore(start) && at.isBefore(end);
      if (t.inMinor > 0) {
        if (inMonth) came += t.inMinor;
        continue;
      }
      // Debits add; card refunds (negative) take back from the same
      // month, category and payee, but aren't a spend of their own.
      final a = t.spentMinor;
      if (a == 0) continue;
      if (perMonth.containsKey(key)) {
        perMonth[key] = perMonth[key]! + a;
      }
      if (!inMonth) continue;

      final one = a > 0 ? 1 : 0;
      spent += a;
      spends += one;
      if (a > 0) {
        dayTotals[at.day - 1] += a;
        final band = Bands.of(a);
        bandTotals[band] += a;
        bandCounts[band]++;
      }

      final c = cats[t.category?.id];
      cats[t.category?.id] = (t.category, (c?.$2 ?? 0) + a, (c?.$3 ?? 0) + one);

      final pk = t.merchantId ?? t.payee.toLowerCase();
      final p = payees[pk];
      final byCat = p?.$4 ?? <String?, (Category?, int)>{};
      final pc = byCat[t.category?.id];
      byCat[t.category?.id] = (t.category, (pc?.$2 ?? 0) + one);
      payees[pk] = (t.payee, (p?.$2 ?? 0) + a, (p?.$3 ?? 0) + one, byCat);
    }
    if (spent < 0) spent = 0;
    perMonth.updateAll((_, v) => v < 0 ? 0 : v);

    final categories = [
      for (final c in cats.values)
        if (c.$2 > 0) CategorySpend(c.$1, c.$2, c.$3),
    ]..sort((a, b) => b.spentMinor.compareTo(a.spentMinor));
    final ranked = [
      for (final p in payees.values)
        if (p.$2 > 0 && p.$3 > 0)
          PayeeSpend(
            p.$1,
            p.$2,
            p.$3,
            (p.$4.values.toList()..sort((a, b) => b.$2.compareTo(a.$2)))
                .first
                .$1,
          ),
    ]..sort((a, b) => b.spentMinor.compareTo(a.spentMinor));

    return MonthReport(
      month: start,
      trend: [for (final e in perMonth.entries) MonthSpend(e.key, e.value)],
      dayTotals: dayTotals,
      categories: categories,
      payees: ranked.take(topPayees).toList(),
      payeeCount: ranked.length,
      bandTotals: bandTotals,
      bandCounts: bandCounts,
      spentMinor: spent,
      inMinor: came,
      spends: spends,
    );
  }
}
