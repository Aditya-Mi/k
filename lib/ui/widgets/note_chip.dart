import 'package:flutter/material.dart';

import '../theme/k_theme.dart';

enum NoteChipStyle {
  /// Money out.
  filled,

  /// Money in: outlined in the band ink.
  outlined,

  /// Pending, upcoming, unparsed: filled at 45%.
  pending,
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
    final ink = context.k.ink(Bands.of(amountMinor));
    return SizedBox(
      width: 24,
      height: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: switch (style) {
            NoteChipStyle.filled => ink,
            NoteChipStyle.outlined => null,
            NoteChipStyle.pending => ink.withValues(alpha: 0.45),
          },
          border: style == NoteChipStyle.outlined
              ? Border.all(color: ink, width: 1.5)
              : null,
          borderRadius: BorderRadius.circular(2),
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
    return Container(
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
    );
  }
}
