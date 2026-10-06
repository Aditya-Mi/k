import 'package:flutter/material.dart';

import '../theme/k_theme.dart';

enum NoteChipStyle {
  /// Money out.
  filled,

  /// Money in: outlined in the band ink.
  outlined,

  /// Pending, unparsed: filled at 45%.
  pending,

  /// Due, not paid (AutoPay alert): dashed text-3 outline with a clock. No
  /// ink, so it can't be read as a payment's band.
  upcoming,

  /// Review card with no amount found: dashed outline with "?".
  unknown,
}

/// 24×12dp note-shaped chip in the amount's band ink.
class NoteChip extends StatelessWidget {
  const NoteChip({
    super.key,
    required this.amountMinor,
    this.style = NoteChipStyle.filled,
  });

  final int amountMinor;
  final NoteChipStyle style;

  @override
  Widget build(BuildContext context) {
    if (style == NoteChipStyle.upcoming || style == NoteChipStyle.unknown) {
      return ExcludeSemantics(child: _DashedChip(style: style));
    }
    final ink = context.k.ink(Bands.of(amountMinor));
    // Decorative: the amount next to it is what a screen reader reads.
    return ExcludeSemantics(
      child: SizedBox(
        width: 24,
        height: 12,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: switch (style) {
              NoteChipStyle.filled => ink,
              NoteChipStyle.outlined => null,
              NoteChipStyle.pending => ink.withValues(alpha: 0.45),
              _ => null,
            },
            border: style == NoteChipStyle.outlined
                ? Border.all(color: ink, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// 60×28dp chip carrying the band's lower bound ("500+"), leads the hero amount.
class LargeNoteChip extends StatelessWidget {
  const LargeNoteChip({
    super.key,
    required this.amountMinor,
    this.outlined = false,
  });

  final int amountMinor;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final band = Bands.of(amountMinor);
    final ink = context.k.ink(band);
    // "500+" next to "₹649" would be read twice; the amount says it all.
    return ExcludeSemantics(
      child: Container(
        width: 60,
        height: 28,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: outlined ? null : ink,
          border: outlined ? Border.all(color: ink, width: 1.5) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: FittedBox(
          child: Text(
            Bands.chipLabels[band],
            style: context.kt.title.copyWith(
              fontSize: 14,
              color: outlined ? ink : context.k.onInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// 24×12dp, 1dp dashed text-3 outline; a clock (upcoming) or "?" (unknown).
class _DashedChip extends StatelessWidget {
  const _DashedChip({required this.style});

  final NoteChipStyle style;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return SizedBox(
      width: 24,
      height: 12,
      child: CustomPaint(
        painter: _DashedRect(c.text3),
        child: Center(
          child: style == NoteChipStyle.upcoming
              ? Icon(Icons.schedule_rounded, size: 8, color: c.text3)
              : Text(
                  '?',
                  style: context.kt.meta.copyWith(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: c.text3,
                  ),
                ),
        ),
      ),
    );
  }
}

class _DashedRect extends CustomPainter {
  _DashedRect(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(2),
        ),
      );
    const dash = 2.5, gap = 2.0;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRect old) => old.color != color;
}
