import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Guilloche rosette geometry (DESIGN.md "The Guilloche Rule").
/// Three hypotrochoid bands at d·0.7, d, d·1.3 plus rings, in a 100-unit
/// space scaled to the widget.
@immutable
class RosetteSpec {
  const RosetteSpec({
    required this.lobes,
    required this.dFactor,
    this.innerRing = true,
  });

  /// The house rosette: 6 lobes, used on the month panel, detail, empty
  /// states, the drawn moment and the app icon.
  static const house = RosetteSpec(lobes: 6, dFactor: 1.26);

  /// Deterministic per-name seal for subscriptions.
  factory RosetteSpec.seal(String name) {
    final h = fnv1a(name);
    return RosetteSpec(
      lobes: 5 + h % 5,
      dFactor: 0.9 + ((h >> 4) % 6) * 0.18,
      innerRing: (h >> 8).isOdd,
    );
  }

  final int lobes;
  final double dFactor;
  final bool innerRing;

  static const _bigR = 100.0;
  double get _r => _bigR / lobes;
  double get _d => _r * dFactor;
  double get outerRadius => _bigR - _r + 1.3 * _d + 3;

  /// Paths in rosette units, centred on the origin.
  List<Path> paths() {
    final r = _r;
    final k = (_bigR - r) / r;
    Path band(double d) {
      final p = Path();
      const steps = 900;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps * 2 * math.pi;
        final x = (_bigR - r) * math.cos(t) + d * math.cos(k * t);
        final y = (_bigR - r) * math.sin(t) - d * math.sin(k * t);
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p..close();
    }

    Path ring(double radius) =>
        Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: radius));

    return [
      band(_d * 0.7),
      band(_d),
      band(_d * 1.3),
      ring(outerRadius),
      if (innerRing) ring(math.max(8.0, (_bigR - r) - 1.3 * _d - 3).abs()),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is RosetteSpec &&
      other.lobes == lobes &&
      other.dFactor == dFactor &&
      other.innerRing == innerRing;

  @override
  int get hashCode => Object.hash(lobes, dFactor, innerRing);
}

/// 32-bit FNV-1a over UTF-8.
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Hairline rosette. [progress] < 1 draws each path partially (the drawn
/// moment); bands are staggered by the caller's animation.
class Rosette extends StatelessWidget {
  const Rosette({
    super.key,
    required this.size,
    required this.color,
    this.spec = RosetteSpec.house,
    this.strokeWidth = 0.6,
    this.progress = 1,
  });

  final double size;
  final Color color;
  final RosetteSpec spec;
  final double strokeWidth;
  final double progress;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: _RosettePainter(spec, color, strokeWidth, progress),
      ),
    ),
  );
}

class _RosettePainter extends CustomPainter {
  _RosettePainter(this.spec, this.color, this.strokeWidth, this.progress);

  final RosetteSpec spec;
  final Color color;
  final double strokeWidth;
  final double progress;

  static final _cache = <RosetteSpec, List<Path>>{};

  @override
  void paint(Canvas canvas, Size size) {
    final paths = _cache.putIfAbsent(spec, spec.paths);
    final scale = (size.shortestSide / 2 - strokeWidth) / spec.outerRadius;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      // Stroke is in screen dp, so divide out the canvas scale.
      ..strokeWidth = strokeWidth / scale;

    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale);
    for (final path in paths) {
      if (progress >= 1) {
        canvas.drawPath(path, paint);
        continue;
      }
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RosettePainter old) =>
      old.spec != spec ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.progress != progress;
}
