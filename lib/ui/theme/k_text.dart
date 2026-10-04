import 'package:flutter/material.dart';

import 'k_colors.dart';

const _archivo = 'Archivo';
const _tnum = [FontFeature.tabularFigures()];

List<FontVariation> _axes(double weight) => [
  FontVariation('wght', weight),
  const FontVariation('wdth', 112),
];

/// DESIGN.md type scale. Archivo (wdth 112, tabular) counts; Roboto reads.
@immutable
class KText {
  KText(KColors c)
    : amountHero = TextStyle(
        fontFamily: _archivo,
        fontSize: 40,
        fontWeight: FontWeight.w700,
        fontVariations: _axes(700),
        fontFeatures: _tnum,
        height: 1.1,
        color: c.text,
      ),
      headline = TextStyle(
        fontFamily: _archivo,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontVariations: _axes(600),
        height: 1.25,
        color: c.text,
      ),
      title = TextStyle(
        fontFamily: _archivo,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontVariations: _axes(600),
        height: 1.3,
        color: c.text,
      ),
      amountRow = TextStyle(
        fontFamily: _archivo,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontVariations: _axes(600),
        fontFeatures: _tnum,
        height: 1.3,
        color: c.text,
      ),
      body = TextStyle(fontSize: 15, height: 1.35, color: c.text),
      meta = TextStyle(
        fontSize: 12.5,
        height: 1.35,
        fontFeatures: _tnum,
        color: c.text2,
      ),
      dayHeader = TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        height: 1.35,
        fontFeatures: _tnum,
        color: c.text2,
      ),
      label = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: c.text2,
      ),
      wordmark = TextStyle(
        fontFamily: _archivo,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        fontVariations: _axes(700),
        color: c.text,
      );

  final TextStyle amountHero;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle amountRow;
  final TextStyle body;
  final TextStyle meta;
  final TextStyle dayHeader;
  final TextStyle label;
  final TextStyle wordmark;
}
