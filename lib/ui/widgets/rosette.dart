import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One hypotrochoid band: x = a·cos t + d·cos(k·t), y = a·sin t − d·sin(k·t),
/// t ∈ [0, 2π]. Draws k + 1 lobes.
@immutable
class Trochoid {
  const Trochoid(this.a, this.d, this.k);

  final double a;
  final double d;
  final int k;

  Path path() {
    final p = Path();
    const steps = 900;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final x = a * math.cos(t) + d * math.cos(k * t);
      final y = a * math.sin(t) - d * math.sin(k * t);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }

  @override
  bool operator ==(Object other) =>
      other is Trochoid && other.a == a && other.d == d && other.k == k;

  @override
  int get hashCode => Object.hash(a, d, k);
}

/// Guilloche rosette geometry (DESIGN.md "The Guilloche Rule"): hypotrochoid
/// bands plus rings, centred on the origin in a ±[extent] unit space that is
/// scaled to the widget.
@immutable
class RosetteSpec {
  const RosetteSpec({
    required this.bands,
    required this.rings,
    required this.extent,
  });

  /// The house rosette from design/k.pen ("Guilloche"): two 6-lobe families
  /// (a 80 and a 65) and four rings. The design's 5-lobe core band
  /// (a 48, d 14) is left out at the owner's request.
  static const house = RosetteSpec(
    bands: [
      Trochoid(80, 22, 5),
      Trochoid(80, 30, 5),
      Trochoid(80, 38, 5),
      Trochoid(65, 18, 5),
      Trochoid(65, 26, 5),
    ],
    rings: [118, 104, 44, 30],
    extent: 120,
  );

  /// Deterministic per-name seal for subscriptions (DESIGN.md generator):
  /// h = FNV-1a(name); lobes = 5 + h mod 5; R = 100, r = R/lobes;
  /// d = r·(0.9 + ((h>>4) mod 6)·0.18); bands at d·0.7, d, d·1.3; outer ring
  /// at R−r+1.3d+3; inner ring when (h>>8) is odd.
  factory RosetteSpec.seal(String name) {
    final h = fnv1a(name);
    final lobes = 5 + h % 5;
    const bigR = 100.0;
    final r = bigR / lobes;
    final d = r * (0.9 + ((h >> 4) % 6) * 0.18);
    final a = bigR - r;
    final outer = a + 1.3 * d + 3;
    return RosetteSpec(
      bands: [
        for (final f in [0.7, 1.0, 1.3]) Trochoid(a, d * f, lobes - 1),
      ],
      rings: [outer, if ((h >> 8).isOdd) math.max(8.0, a - 1.3 * d - 3)],
      extent: outer + 2,
    );
  }

  final List<Trochoid> bands;
  final List<double> rings;
  final double extent;

  /// Paths in rosette units, bands first so the drawn moment strokes them
  /// before the rings.
  List<Path> paths() => [
    for (final b in bands) b.path(),
    for (final r in rings)
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)),
  ];

  @override
  bool operator ==(Object other) =>
      other is RosetteSpec &&
      other.extent == extent &&
      _listEq(other.bands, bands) &&
      _listEq(other.rings, rings);

  @override
  int get hashCode =>
      Object.hash(extent, Object.hashAll(bands), Object.hashAll(rings));
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

/// Hairline rosette. [progress] < 1 draws each path partially, staggered —
/// the drawn moment (DESIGN.md Motion).
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
    final scale = size.shortestSide / 2 / spec.extent;
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
    // Drawn moment: each path starts 40ms after the previous in a 600ms draw.
    const stagger = 40 / 600;
    final span = 1 - (paths.length - 1) * stagger;
    for (final (i, path) in paths.indexed) {
      final p = progress >= 1
          ? 1.0
          : ((progress - i * stagger) / span).clamp(0.0, 1.0);
      if (p >= 1) {
        canvas.drawPath(path, paint);
        continue;
      }
      if (p <= 0) continue;
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * p), paint);
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
