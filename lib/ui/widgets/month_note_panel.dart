import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/k_theme.dart';
import 'rosette.dart';

/// What the month panel shows; computed from the month's transactions.
class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.spentMinor,
    required this.inMinor,
    required this.spends,
    required this.bandTotals,
  });

  static MonthSummary empty(DateTime month) => MonthSummary(
    month: month,
    spentMinor: 0,
    inMinor: 0,
    spends: 0,
    bandTotals: List.filled(Bands.count, 0),
  );

  final DateTime month;
  final int spentMinor;
  final int inMinor;
  final int spends;

  /// Spend per band (debits only), index = band.
  final List<int> bandTotals;

  /// Band with the biggest share of spend, or null when nothing was spent.
  int? get dominantBand {
    if (spentMinor == 0) return null;
    var best = 0;
    for (var i = 1; i < bandTotals.length; i++) {
      if (bandTotals[i] > bandTotals[best]) best = i;
    }
    return best;
  }
}

/// The signature month card: total, in/out line, spend-size ribbon and the
/// house rosette in the month total's ink.
class MonthNotePanel extends StatelessWidget {
  const MonthNotePanel({
    super.key,
    required this.summary,
    this.syncedAt,
    this.label,
    this.showLeft = false,
  });

  final MonthSummary summary;
  final DateTime? syncedAt;

  /// Replaces the month name in the head (Summary: "So far this month",
  /// since its top bar already names the month).
  final String? label;

  /// Adds "₹X left" (came in − spent) to the in/out line.
  final bool showLeft;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final s = summary;
    // Nothing spent → no amount to ink; neutral like the lock screen.
    final ink = s.spentMinor == 0 ? c.text2 : c.ink(Bands.of(s.spentMinor));
    final dominant = s.dominantBand;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AspectRatio(
        aspectRatio: 2.07,
        child: LayoutBuilder(
          builder: (context, box) {
            // Placement from design/k.pen: 136dp in a 380×184 panel, flush
            // with the top, 7dp in from the right — whole, clear of the ribbon.
            final unit = box.maxHeight / 184;
            final rosette = 136 * unit;
            return Stack(
              children: [
                Positioned(
                  right: 7 * unit,
                  top: 0,
                  child: Rosette(size: rosette, color: ink, strokeWidth: 0.5),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label ?? monthYear(s.month),
                            style: t.title.copyWith(color: c.text2),
                          ),
                          if (syncedAt != null) ...[
                            const SizedBox(width: 12),
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 14,
                              color: c.text3,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Synced ${_synced(syncedAt!)}',
                              style: t.meta.copyWith(color: c.text3),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(inr(s.spentMinor), style: t.amountHero),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          label != null || !_isOpen(s.month)
                              ? 'spent'
                              : 'spent so far',
                          if (s.inMinor > 0) '${inr(s.inMinor)} came in',
                          if (showLeft && s.inMinor > s.spentMinor)
                            '${inr(s.inMinor - s.spentMinor)} left',
                        ].join('  ·  '),
                        style: t.body.copyWith(color: c.text2),
                      ),
                      const Spacer(),
                      SpendRibbon(bandTotals: s.bandTotals),
                      const SizedBox(height: 8),
                      Text(
                        dominant == null
                            ? 'No spends yet'
                            : '${s.spends} ${s.spends == 1 ? 'spend' : 'spends'}'
                                  '  ·  ${Bands.ranges[dominant]} spends make up '
                                  '${(s.bandTotals[dominant] * 100 / s.spentMinor).round()}% of it',
                        style: t.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _isOpen(DateTime month) {
    final now = DateTime.now();
    return month.year == now.year && month.month == now.month;
  }

  String _synced(DateTime at) {
    final now = DateTime.now();
    return dateOnly(at) == dateOnly(now) ? hhmm(at) : dayMonth(at);
  }
}

/// One rounded bar split into band segments, proportional to spend share.
class SpendRibbon extends StatelessWidget {
  const SpendRibbon({super.key, required this.bandTotals, this.height = 8});

  final List<int> bandTotals;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final total = bandTotals.fold(0, (a, b) => a + b);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: total == 0
            ? ColoredBox(color: c.surface3)
            : Row(
                // Stretch, or childless ColoredBoxes collapse to zero height.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < bandTotals.length; i++)
                    if (bandTotals[i] > 0)
                      Expanded(
                        // Thin bands still show as a sliver.
                        flex: (bandTotals[i] * 1000 ~/ total).clamp(8, 1000),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: ColoredBox(color: c.ink(i)),
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}
