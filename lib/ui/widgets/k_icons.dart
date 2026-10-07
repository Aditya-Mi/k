import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

/// k's own hairline icons (design: "Icons — hairline set" in k.pen).
/// 24 grid, 1.5 stroke. [note] is the 2:1 note shape; it fills when the
/// icon is selected (ambient `IconTheme.fill` > 0, as the nav bar sets).
class KIconData {
  const KIconData(this.lines, this.note);
  final String? lines;
  final String? note;
}

abstract final class KIcons {
  static const transactions = KIconData(
    'M10.5 6.75H21M10.5 12H21M10.5 17.25H17',
    'M3 5.5h5V8H3zM3 10.75h5v2.5H3zM3 16h5v2.5H3z',
  );
  static const review = KIconData(
    'M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H10l-4 3.5V17H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM7 8.5h10',
    'M7 11.25h6v3H7z',
  );
  static const recurring = KIconData(
    'M20 12a8 8 0 1 1-8-8c2.24 0 4.38.89 5.99 2.43L20 8.5M20 4v4.5h-4.5',
    'M9.5 10.75h5v2.5h-5z',
  );
  static const accounts = KIconData(
    'M5 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2zM6 7V5.5a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1V7',
    'M14 12.25h5v2.5h-5z',
  );
  static const summary = KIconData(
    null,
    'M3 5h18v2.5H3zM3 10.75h12v2.5H3zM3 16.5h7V19H3z',
  );

  /// Self transfer, ATM → cash, card bill: money moving between own pots.
  static const transfer = KIconData(
    'M4 8.5h15M15.5 5L19 8.5 15.5 12M20 15.5H5M8.5 12L5 15.5 8.5 19',
    null,
  );

  /// More than one message became one payment.
  static const merged = KIconData(
    'M6 4v3a5 5 0 0 0 5 5h1M18 4v3a5 5 0 0 1-5 5h-1M12 12v8',
    null,
  );
}

/// Draws a [KIconData] like an [Icon]: size and colour from the ambient
/// [IconTheme] unless given.
class KIcon extends StatelessWidget {
  const KIcon(this.icon, {super.key, this.size, this.color, this.selected});

  final KIconData icon;
  final double? size;
  final Color? color;

  /// Fill the note shape. Defaults to `IconTheme.fill > 0`.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: _KIconPainter(
          icon,
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
          selected ?? (theme.fill ?? 0) > 0,
        ),
      ),
    );
  }
}

final _paths = <String, Path>{};
Path _parse(String d) => _paths.putIfAbsent(d, () => parseSvgPathData(d));

class _KIconPainter extends CustomPainter {
  _KIconPainter(this.icon, this.color, this.selected);

  final KIconData icon;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (icon.lines case final d?) canvas.drawPath(_parse(d), stroke);
    if (icon.note case final d?) {
      final p = _parse(d);
      if (selected) {
        canvas.drawPath(p, Paint()..color = color);
      }
      canvas.drawPath(p, stroke);
    }
  }

  @override
  bool shouldRepaint(_KIconPainter old) =>
      old.icon != icon || old.color != color || old.selected != selected;
}
