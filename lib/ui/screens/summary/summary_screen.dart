import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/summary/month_report.dart';
import '../../../data/emis/emi_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/month_note_panel.dart';
import '../../widgets/txn_row.dart';
import '../accounts/accounts_screen.dart';
import '../txn_detail/txn_detail_screen.dart';

/// Where the month went (design 05): the month panel, six months of spend,
/// the month as a calendar of inked days, categories, top payees and spend
/// sizes. Self transfers are never spend.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final _ledger = getIt<LedgerRepository>();
  late DateTime _month = _thisMonth;
  late Stream<(MonthReport, List<TxnView>)> _data = _watch();
  late final Stream<DateTime?> _synced = getIt<SettingsRepository>().watchDate(
    SettingsRepository.smsLastSyncAt,
  );

  /// Shown while a newly picked month loads, so the screen doesn't blank.
  (MonthReport, List<TxnView>)? _last;

  static DateTime get _thisMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  Stream<(MonthReport, List<TxnView>)> _watch() {
    final m = _month;
    return _ledger
        .watchTransactions(
          TxnFilter(
            from: DateTime(m.year, m.month - (MonthReport.trendMonths - 1)),
            to: DateTime(m.year, m.month + 1),
          ),
        )
        .asyncMap((txns) async {
          // Spread card EMIs count an instalment a month.
          final virtual = await getIt<EmiService>().virtualInstalments([
            for (var i = MonthReport.trendMonths - 1; i >= 0; i--)
              DateTime(m.year, m.month - i),
          ]);
          return (MonthReport.build(m, [...txns, ...virtual]), txns);
        });
  }

  void _go(DateTime month) {
    final m = DateTime(month.year, month.month);
    if (m.isAfter(_thisMonth) || m == _month) return;
    setState(() {
      _month = m;
      _data = _watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final isCurrent = _month == _thisMonth;
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _go(DateTime(_month.year, _month.month - 1)),
              ),
              Expanded(
                child: Text(
                  monthYear(_month),
                  style: t.headline,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: isCurrent
                    ? null
                    : () => _go(DateTime(_month.year, _month.month + 1)),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<(MonthReport, List<TxnView>)>(
            stream: _data,
            builder: (context, snap) {
              final fresh = snap.data;
              if (fresh != null && fresh.$1.month == _month) _last = fresh;
              final data = _last;
              if (data == null) return const SizedBox.shrink();
              final (r, txns) = data;
              final shownCurrent = r.month == _thisMonth;
              return StreamBuilder<DateTime?>(
                stream: _synced,
                builder: (context, sync) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    MonthNotePanel(
                      summary: MonthSummary(
                        month: r.month,
                        spentMinor: r.spentMinor,
                        inMinor: r.inMinor,
                        spends: r.spends,
                        bandTotals: r.bandTotals,
                      ),
                      syncedAt: shownCurrent ? sync.data : null,
                      label: shownCurrent ? 'So far this month' : 'All month',
                      showLeft: true,
                    ),
                    const SizedBox(height: 8),
                    const _AccountsTotal(),
                    const SizedBox(height: 20),
                    _Section(
                      title: 'Last 6 months',
                      meta: r.trendAverage == null
                          ? null
                          : 'avg ${inr(r.trendAverage!)} a month',
                      child: _TrendChart(
                        trend: r.trend,
                        current: shownCurrent,
                        onTap: _go,
                      ),
                    ),
                    if (r.spends == 0) ...[
                      const SizedBox(height: 28),
                      Text(
                        shownCurrent
                            ? 'Nothing spent yet this month.'
                            : 'Nothing spent in ${DateFormat('MMMM').format(r.month)}.',
                        style: t.body.copyWith(color: c.text2),
                      ),
                    ] else ...[
                      const SizedBox(height: 28),
                      _Section(
                        title: 'Day by day',
                        meta: _bigDays(r),
                        child: _Calendar(
                          report: r,
                          onDay: (day) => _openDay(context, day, txns),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _Section(
                        title: 'Where it went',
                        child: _Categories(report: r),
                      ),
                      const SizedBox(height: 28),
                      _Section(
                        title: 'Top payees',
                        meta:
                            '${r.payeeCount} ${r.payeeCount == 1 ? 'payee' : 'payees'}',
                        child: _Payees(report: r),
                      ),
                      const SizedBox(height: 28),
                      _Section(
                        title: 'By spend size',
                        child: _SpendSizes(report: r),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String? _bigDays(MonthReport r) {
    final n = r.dayTotals.where((d) => d >= Bands.lowerMinor.last).length;
    return n == 0 ? null : '$n ${n == 1 ? 'day' : 'days'} over ₹2,000';
  }

  Future<void> _openDay(BuildContext context, int day, List<TxnView> all) {
    final month = _last?.$1.month ?? _month;
    final date = DateTime(month.year, month.month, day);
    final rows = [
      for (final t in all)
        if (dateOnly(t.occurredAt) == date) t,
    ];
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(dayShort(date), style: context.kt.title),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in rows)
                      TxnRow(
                        txn: t,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TxnDetailScreen(txnId: t.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "In your accounts · ₹49,890 ›": the Accounts total, opens Accounts.
class _AccountsTotal extends StatelessWidget {
  const _AccountsTotal();

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return StreamBuilder<List<AccountRowData>>(
      stream: AccountsScreen.rows(),
      builder: (context, snap) {
        final rows = snap.data;
        if (rows == null || rows.every((r) => r.balance == null)) {
          return const SizedBox.shrink();
        }
        return FieldRow(
          label: 'In your accounts',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
          ),
          value: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                signedInr(accountsTotal(rows).totalMinor),
                style: t.amountRow,
              ),
              Icon(Icons.chevron_right_rounded, color: context.k.text2),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.meta});

  final String title;
  final String? meta;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(title, style: t.title)),
            if (meta != null) Text(meta!, style: t.meta),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

/// Six months of spend: past months outlined, the open month filled.
class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.trend,
    required this.current,
    required this.onTap,
  });

  final List<MonthSpend> trend;

  /// The last month is still running ("so far").
  final bool current;
  final ValueChanged<DateTime> onTap;

  static const _barMax = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final max = trend.fold(0, (a, m) => m.spentMinor > a ? m.spentMinor : a);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, m) in trend.indexed)
            Expanded(
              child: Builder(
                builder: (context) {
                  final last = i == trend.length - 1;
                  // Filled only while the month is still running; a viewed
                  // closed month gets a heavier outline instead.
                  final open = last && current;
                  final h = max == 0 ? 0.0 : _barMax * m.spentMinor / max;
                  final tone = last ? c.text : c.text2;
                  return Semantics(
                    button: true,
                    label: '${monthYear(m.month)}: ${inr(m.spentMinor)}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onTap(m.month),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _fit(
                            Text(
                              m.spentMinor == 0 ? '–' : _short(m.spentMinor),
                              maxLines: 1,
                              style: t.meta.copyWith(
                                fontFamily: t.amountRow.fontFamily,
                                fontVariations: t.amountRow.fontVariations,
                                fontFeatures: t.amountRow.fontFeatures,
                                fontSize: 11.5,
                                fontWeight: last
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: tone,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 30,
                            height: h < 2 ? 2 : h,
                            decoration: BoxDecoration(
                              color: open ? c.text : null,
                              border: open
                                  ? null
                                  : Border.all(
                                      color: tone,
                                      width: last ? 1.5 : 1,
                                    ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                                bottom: Radius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _fit(
                            Text(
                              '${DateFormat('MMM').format(m.month)}'
                              '${open ? ' so far' : ''}',
                              maxLines: 1,
                              style: t.meta.copyWith(
                                fontSize: 12,
                                fontWeight: last
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: tone,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static Widget _fit(Widget w) => FittedBox(fit: BoxFit.scaleDown, child: w);

  /// ₹48.2k, ₹1.1L.
  static String _short(int minor) {
    final r = minor / 100;
    if (r >= 100000) return '₹${_trim(r / 100000)}L';
    if (r >= 1000) return '₹${_trim(r / 1000)}k';
    return '₹${r.round()}';
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}

/// The month as rows of note-shaped days, each in the ink of its spend.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.report, required this.onDay});

  final MonthReport report;
  final ValueChanged<int> onDay;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final month = report.month;
    final lead = month.weekday - 1; // Monday first
    final days = report.dayTotals.length;
    final today = dateOnly(DateTime.now());
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    final big = report.biggestDay;

    Widget cell(int i) {
      final day = i - lead + 1;
      if (day < 1 || day > days) return const SizedBox(height: 34);
      final date = DateTime(month.year, month.month, day);
      final future = date.isAfter(today);
      final spent = report.dayTotals[day - 1];
      final isToday = date == today;
      final fill = future
          ? c.surface1
          : spent > 0
          ? c.ink(Bands.of(spent))
          : null;
      final label = Text(
        '$day',
        style: t.meta.copyWith(
          fontFamily: t.amountRow.fontFamily,
          fontVariations: t.amountRow.fontVariations,
          fontFeatures: t.amountRow.fontFeatures,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: spent > 0 && !future ? c.onInk : c.text3,
        ),
      );
      final box = Container(
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(4),
          border: isToday
              ? Border.all(
                  color: c.text,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                )
              : fill == null
              ? Border.all(color: c.outline)
              : null,
        ),
        child: label,
      );
      final tappable = spent > 0 && !future;
      // The 6dp gaps sit inside each cell so the whole pitch is tappable.
      return Semantics(
        button: tappable,
        label:
            '${dayShort(date)}: '
            '${future
                ? 'ahead'
                : spent > 0
                ? inr(spent)
                : 'no spend'}',
        excludeSemantics: true,
        child: InkWell(
          onTap: tappable ? () => onDay(day) : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(padding: const EdgeInsets.all(3), child: box),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final w in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) ...[
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: t.label.copyWith(fontSize: 11.5, color: c.text3),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var d = 0; d < 7; d++) Expanded(child: cell(r * 7 + d)),
            ],
          ),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: Text(
                big == null
                    ? ''
                    : 'Biggest day: '
                          '${dayShort(DateTime(month.year, month.month, big.$1))}, '
                          '${inr(big.$2)}',
                style: t.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text('small', style: t.meta.copyWith(fontSize: 11, color: c.text3)),
            const SizedBox(width: 4),
            for (var b = 0; b < Bands.count; b++)
              Container(
                width: 12,
                height: 6,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color: c.ink(b),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            const SizedBox(width: 1),
            Text('big', style: t.meta.copyWith(fontSize: 11, color: c.text3)),
          ],
        ),
      ],
    );
  }
}

/// Categories, biggest first, with neutral bars (inks never mark a category).
class _Categories extends StatelessWidget {
  const _Categories({required this.report});

  final MonthReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final max = report.categories.first.spentMinor;
    return Column(
      children: [
        for (final (i, s) in report.categories.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            children: [
              Icon(categoryIcon(s.category?.icon), size: 20, color: c.text2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.category?.name ?? 'Uncategorized',
                  style: t.body.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${(s.spentMinor * 100 / report.spentMinor).round()}%',
                style: t.meta.copyWith(color: c.text3),
              ),
              const SizedBox(width: 10),
              Text(
                inr(s.spentMinor),
                style: t.amountRow.copyWith(fontSize: 14.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (s.spentMinor / max).clamp(0.02, 1.0),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: c.text,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Payees extends StatelessWidget {
  const _Payees({required this.report});

  final MonthReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Column(
      children: [
        for (final (i, p) in report.payees.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: i == report.payees.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: c.outline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.payee,
                        style: t.body.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          '${p.count} ${p.count == 1 ? 'payment' : 'payments'}',
                          ?p.category?.name,
                        ].join(' · '),
                        style: t.meta,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(inr(p.spentMinor), style: t.amountRow),
              ],
            ),
          ),
      ],
    );
  }
}

/// Spend per band: the one place on this screen where bars carry ink.
class _SpendSizes extends StatelessWidget {
  const _SpendSizes({required this.report});

  final MonthReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final r = report;
    final max = r.bandTotals.fold(0, (a, b) => b > a ? b : a);
    final bigIndex = Bands.count - 1;
    final bigCount = r.bandCounts[bigIndex];
    final smallCount = r.spends - bigCount;
    final smallTotal = r.spentMinor - r.bandTotals[bigIndex];
    final caption = bigCount == 0 || smallCount == 0
        ? null
        : '$smallCount small ${smallCount == 1 ? 'spend' : 'spends'} under '
              '₹2,000 add up to ${smallTotal < r.bandTotals[bigIndex] ? 'less' : 'more'} '
              'than the $bigCount big ${bigCount == 1 ? 'one' : 'ones'}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null) ...[
          Text(caption, style: t.body.copyWith(fontSize: 13.5, color: c.text2)),
          const SizedBox(height: 10),
        ],
        for (var b = 0; b < Bands.count; b++)
          if (r.bandCounts[b] > 0)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            Bands.rowLabels[b],
                            style: t.amountRow.copyWith(fontSize: 13.5),
                          ),
                        ),
                        Text(
                          '${r.bandCounts[b]} ${r.bandCounts[b] == 1 ? 'spend' : 'spends'}',
                          style: t.meta.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 12,
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: FractionallySizedBox(
                        widthFactor: (r.bandTotals[b] / max).clamp(0.02, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.ink(b),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        inr(r.bandTotals[b]),
                        style: t.amountRow.copyWith(fontSize: 14.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
