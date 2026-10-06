import 'package:flutter/material.dart';

/// Motion tokens (DESIGN.md Motion). Functional motion only: feedback,
/// state change, continuity. Everything is instant under Android's
/// "Remove animations" (`MediaQuery.disableAnimations`).
abstract final class Motion {
  /// Feedback and small state changes.
  static const short = Duration(milliseconds: 150);

  /// Routine state change: tab switch, list item in/out.
  static const medium = Duration(milliseconds: 220);

  /// Values settling: totals, bars, ribbon.
  static const long = Duration(milliseconds: 300);

  static const enter = Easing.emphasizedDecelerate;
  static const exit = Easing.emphasizedAccelerate;
  static const standard = Easing.standard;

  static bool off(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero when animations are off.
  static Duration of(BuildContext context, Duration d) =>
      off(context) ? Duration.zero : d;
}

/// Fade-through between the bottom-nav tabs (M3): the old tab fades out,
/// the new one fades in while scaling up from 92%. Every tab stays mounted
/// (state and scroll kept), like the [IndexedStack] it replaces.
class FadeThroughStack extends StatefulWidget {
  const FadeThroughStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<FadeThroughStack> createState() => _FadeThroughStackState();
}

class _FadeThroughStackState extends State<FadeThroughStack>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: 1,
  );
  late int _from = widget.index;

  // Out over the first 35%, in over the rest (M3 fade through).
  late final _fadeOut = ReverseAnimation(
    CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.35, curve: Motion.exit),
    ),
  );
  late final _fadeIn = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.35, 1, curve: Motion.enter),
  );
  late final _scaleIn = Tween<double>(begin: 0.92, end: 1).animate(_fadeIn);

  @override
  void didUpdateWidget(FadeThroughStack old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    _from = old.index;
    if (Motion.off(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final running = _c.isAnimating;
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final (i, child) in widget.children.indexed)
              _layer(i, child, running),
          ],
        );
      },
    );
  }

  // Same widget shape for every layer in every frame, so no tab loses state.
  Widget _layer(int i, Widget child, bool running) {
    final current = i == widget.index;
    final leaving = running && i == _from && !current;
    final Animation<double> opacity = current
        ? _fadeIn
        : leaving
        ? _fadeOut
        : kAlwaysCompleteAnimation;
    final Animation<double> scale = current
        ? _scaleIn
        : kAlwaysCompleteAnimation;
    final hidden = !current && !leaving;
    return Offstage(
      offstage: hidden,
      child: TickerMode(
        enabled: !hidden,
        child: IgnorePointer(
          ignoring: !current,
          child: FadeTransition(
            opacity: opacity,
            child: ScaleTransition(
              scale: scale,
              child: KeyedSubtree(key: ValueKey(i), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// [PredictiveBackPageTransitionsBuilder] (Android's fade-forwards, and the
/// predictive back gesture), cut instantly when animations are off.
class KPageTransitionsBuilder extends PageTransitionsBuilder {
  const KPageTransitionsBuilder();

  static const _inner = PredictiveBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _inner.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final inner = _inner.delegatedTransition;
    if (inner == null) return null;
    return (context, animation, secondary, snapshot, child) =>
        Motion.off(context)
        ? child
        : inner(context, animation, secondary, snapshot, child);
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => Motion.off(context)
      ? child
      : _inner.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}

/// A whole-rupee figure that rolls to its new value (month totals).
class RollingAmount extends StatelessWidget {
  const RollingAmount({
    super.key,
    required this.minor,
    required this.format,
    this.style,
  });

  final int minor;
  final String Function(int minor) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: minor.toDouble()),
      duration: Motion.of(context, Motion.long),
      curve: Motion.enter,
      builder: (context, v, _) => Text(
        // Land exactly on the real value.
        format(v.round() == minor ? minor : (v / 100).round() * 100),
        style: style,
      ),
    );
  }
}

/// A row that just arrived while its list was on screen ("did it log"):
/// it opens its space, fades in, and its background holds a surface-2 wash
/// that then clears. Rows that were already there render plainly.
class Arrival extends StatefulWidget {
  const Arrival({super.key, required this.arrivedAt, required this.child});

  /// When the row first showed up; null for rows that were already there.
  final DateTime? arrivedAt;
  final Widget child;

  /// Arrivals older than this render plainly (scrolled back to later).
  static const window = Duration(milliseconds: 600);

  @override
  State<Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<Arrival> with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 1600);

  // 0–14%: open + fade in (≈220ms); hold the wash; 75–100%: wash clears.
  late final _c = AnimationController(vsync: this, duration: _total, value: 1);
  late final _open = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.14, curve: Motion.enter),
  );
  late final _wash = ReverseAnimation(
    CurvedAnimation(
      parent: _c,
      curve: const Interval(0.75, 1, curve: Motion.standard),
    ),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _maybeRun();
  }

  @override
  void didUpdateWidget(Arrival old) {
    super.didUpdateWidget(old);
    if (old.arrivedAt != widget.arrivedAt) _maybeRun();
  }

  void _maybeRun() {
    final at = widget.arrivedAt;
    if (at == null) return;
    if (DateTime.now().difference(at) > Arrival.window) return;
    if (Motion.off(context)) {
      // No movement: the wash shows, then cuts.
      _c.value = 0.5;
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _c.value = 1;
      });
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wash = Theme.of(context).colorScheme.surfaceContainerHigh;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // One shape whether running or not, so the row keeps its state.
        return SizeTransition(
          sizeFactor: _open,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _open,
            child: ColoredBox(
              color: wash.withValues(alpha: _wash.value),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Shared-axis X between siblings (the next review message, the next
/// month): the old one slides out left and fades, the new one slides in
/// from the right. [forward] false reverses the direction.
class SharedAxisSwitcher extends StatelessWidget {
  const SharedAxisSwitcher({
    super.key,
    required this.child,
    this.forward = true,
  });

  /// Keyed by what it shows; a new key runs the transition.
  final Widget child;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    final current = child.key;
    final dir = forward ? 1.0 : -1.0;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (top, previous) =>
          Stack(alignment: Alignment.topCenter, children: [...previous, ?top]),
      transitionBuilder: (child, animation) {
        final incoming = child.key == current;
        final slide = Tween<Offset>(
          begin: Offset((incoming ? 0.08 : -0.08) * dir, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: child,
    );
  }
}
