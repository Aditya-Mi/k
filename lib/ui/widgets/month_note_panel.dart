import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../format.dart';
import '../motion.dart';
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

  /// Adds "net ₹X" (came in − spent; "net −₹X" when more went out). Not
  /// "left": k has no budgets.
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
                  // The ink moves with the total's band.
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: ink),
                    duration: Motion.of(context, Motion.long),
                    curve: Motion.standard,
                    builder: (context, color, _) => Rosette(
                      size: rosette,
                      color: color ?? ink,
                      strokeWidth: 0.5,
                    ),
                  ),
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
                              Symbols.check_circle,
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
                        child: RollingAmount(
                          minor: s.spentMinor,
                          format: inr,
                          style: t.amountHero,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          label != null || !_isOpen(s.month)
                              ? 'spent'
                              : 'spent so far',
                          if (s.inMinor > 0)
                            showLeft
                                ? '${inr(s.inMinor)} in'
                                : '${inr(s.inMinor)} came in',
                          if (showLeft && s.inMinor > 0)
                            'Net ${s.inMinor < s.spentMinor ? '−' : ''}'
                                '${inr(s.inMinor - s.spentMinor)}',
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
/// Segments slide to their new widths when the month's spend changes.
class SpendRibbon extends StatelessWidget {
  const SpendRibbon({super.key, required this.bandTotals, this.height = 8});

  final List<int> bandTotals;
  final double height;

  /// Each band's share of the bar; thin bands still show as a sliver.
  static List<double> shares(List<int> bandTotals) {
    final total = bandTotals.fold(0, (a, b) => a + b);
    if (total == 0) return List.filled(bandTotals.length, 0);
    final raw = [
      for (final b in bandTotals) b == 0 ? 0.0 : (b / total).clamp(0.008, 1.0),
    ];
    final sum = raw.fold(0.0, (a, b) => a + b);
    return [for (final r in raw) r / sum];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return TweenAnimationBuilder<List<double>>(
      tween: _SharesTween(end: shares(bandTotals)),
      duration: Motion.of(context, Motion.long),
      curve: Motion.enter,
      builder: (context, s, _) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _RibbonPainter(
            shares: s,
            inks: [for (var i = 0; i < s.length; i++) c.ink(i)],
            track: c.surface3,
          ),
        ),
      ),
    );
  }
}

class _SharesTween extends Tween<List<double>> {
  _SharesTween({super.end});

  @override
  List<double> lerp(double t) {
    final a = begin!, b = end!;
    if (a.length != b.length) return b;
    return [for (var i = 0; i < b.length; i++) a[i] + (b[i] - a[i]) * t];
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({
    required this.shares,
    required this.inks,
    required this.track,
  });

  final List<double> shares;
  final List<Color> inks;
  final Color track;

  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height);
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, r));
    final total = shares.fold(0.0, (a, b) => a + b);
    if (total < 0.001) {
      canvas.drawRect(Offset.zero & size, Paint()..color = track);
      return;
    }
    var x = 0.0;
    for (var i = 0; i < shares.length; i++) {
      final w = size.width * shares[i] / total;
      // The gap shrinks with the segment, so a band growing from nothing
      // never pops in.
      final drawn = w - (w < _gap * 2 ? w / 2 : _gap);
      if (drawn > 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, drawn, size.height),
          Paint()..color = inks[i],
        );
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.track != track ||
      !_same(old.shares, shares) ||
      !_same(old.inks, inks);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
