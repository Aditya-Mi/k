import 'package:flutter/material.dart';

/// DESIGN.md colour tokens. Dark is primary; light is the paper twin.
@immutable
class KColors extends ThemeExtension<KColors> {
  const KColors({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.outline,
    required this.text,
    required this.text2,
    required this.text3,
    required this.onInk,
    required this.alert,
    required this.alertBg,
    required this.inks,
  });

  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color outline;
  final Color text;
  final Color text2;
  final Color text3;
  final Color onInk;
  final Color alert;
  final Color alertBg;

  /// Spend-band inks, index = band (see bands.dart). One job: encode amount size.
  final List<Color> inks;

  Color ink(int band) => inks[band];

  static const dark = KColors(
    bg: Color(0xFF101114),
    surface1: Color(0xFF17181C),
    surface2: Color(0xFF1F2126),
    surface3: Color(0xFF2A2C33),
    outline: Color(0xFF34363E),
    text: Color(0xFFECEAE4),
    text2: Color(0xFFA9A79F),
    text3: Color(0xFF8C8A82),
    onInk: Color(0xFF101114),
    alert: Color(0xFFFF8A65),
    alertBg: Color(0xFF3A2019),
    inks: [
      Color(0xFFB07A52), // ink-10
      Color(0xFFB9C46A), // ink-20
      Color(0xFF4CC3D9), // ink-50
      Color(0xFFA79BE0), // ink-100
      Color(0xFFF2B705), // ink-200
      Color(0xFFA8A59B), // ink-500
      Color(0xFFE0609A), // ink-2000
    ],
  );

  static const light = KColors(
    bg: Color(0xFFF6F4EE),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEEBE3),
    surface3: Color(0xFFE3DFD5),
    outline: Color(0xFFD3CEC2),
    text: Color(0xFF17181C),
    text2: Color(0xFF55534C),
    text3: Color(0xFF69665D),
    onInk: Color(0xFFFFFFFF),
    alert: Color(0xFFB23A1B),
    alertBg: Color(0xFFFBE3DA),
    inks: [
      Color(0xFF7A4A2A),
      Color(0xFF626E14),
      Color(0xFF0F7486),
      Color(0xFF5845B0),
      Color(0xFF835F00),
      Color(0xFF66635A),
      Color(0xFFA51E5E),
    ],
  );

  @override
  KColors copyWith() => this;

  @override
  KColors lerp(KColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
