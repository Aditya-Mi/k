import 'package:flutter/material.dart';

import '../motion.dart';
import 'k_colors.dart';
import 'k_text.dart';

export 'bands.dart';
export 'k_colors.dart';
export 'k_text.dart';

/// Material Symbols Outlined weight: thin lines to sit with the hairline rosettes.
const _iconWeight = 300.0;

final _darkText = KText(KColors.dark);
final _lightText = KText(KColors.light);

extension KThemeContext on BuildContext {
  KColors get k => Theme.of(this).extension<KColors>()!;
  KText get kt =>
      Theme.of(this).brightness == Brightness.dark ? _darkText : _lightText;
}

/// Material 3 base widgets restyled to DESIGN.md: flat, no shadows, no
/// brand hue — primary is the text colour itself.
ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? KColors.dark : KColors.light;
  final t = brightness == Brightness.dark ? _darkText : _lightText;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.text,
    onPrimary: c.onInk,
    secondary: c.text2,
    onSecondary: c.onInk,
    error: c.alert,
    onError: c.onInk,
    surface: c.bg,
    onSurface: c.text,
    onSurfaceVariant: c.text2,
    surfaceContainerLowest: c.bg,
    surfaceContainerLow: c.surface1,
    surfaceContainer: c.surface1,
    surfaceContainerHigh: c.surface2,
    surfaceContainerHighest: c.surface3,
    outline: c.outline,
    outlineVariant: c.outline,
    secondaryContainer: c.surface3,
    onSecondaryContainer: c.text,
    shadow: Colors.transparent,
    surfaceTint: Colors.transparent,
  );
  const pill = StadiumBorder();
  final titleStyle = WidgetStatePropertyAll(t.title);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    iconTheme: IconThemeData(color: c.text, weight: _iconWeight),
    dividerColor: c.outline,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    // One page transition app-wide, with Android predictive back.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: KPageTransitionsBuilder()},
    ),
    textTheme: TextTheme(
      headlineSmall: t.headline,
      titleMedium: t.title,
      bodyLarge: t.body,
      bodyMedium: t.body,
      bodySmall: t.meta,
      labelMedium: t.label,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: t.headline,
    ),
    dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface1,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: c.surface3,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? t.label.copyWith(color: c.text, fontWeight: FontWeight.w700)
            : t.label,
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? c.text : c.text2,
          weight: _iconWeight,
          fill: s.contains(WidgetState.selected) ? 1 : 0,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(c.text),
        foregroundColor: WidgetStatePropertyAll(c.onInk),
        textStyle: titleStyle,
        shape: const WidgetStatePropertyAll(pill),
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(c.text),
        textStyle: titleStyle,
        shape: const WidgetStatePropertyAll(pill),
        side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
        minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(c.text),
        textStyle: titleStyle,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.surface3 : null,
        ),
        foregroundColor: WidgetStatePropertyAll(c.text),
        side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.text : c.surface3,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.bg : c.text2,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface1,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.outline,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface2,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: t.headline,
      contentTextStyle: t.body.copyWith(color: c.text2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: t.body.copyWith(color: c.onInk),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: t.input.copyWith(color: c.text3),
      border: InputBorder.none,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.text,
      linearTrackColor: c.surface3,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.text : null,
      ),
      checkColor: WidgetStatePropertyAll(c.onInk),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(c.text)),
  );
}
