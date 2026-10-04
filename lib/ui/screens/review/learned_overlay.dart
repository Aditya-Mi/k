import 'package:flutter/material.dart';

import '../../theme/k_theme.dart';
import '../../widgets/rosette.dart';

/// The one authored moment: the house rosette draws itself in the amount's
/// ink over a scrim card saying what was learned. 600ms draw (emphasized
/// decelerate, staggered bands), 400ms hold, 200ms fade. With animations
/// off it appears drawn.
Future<void> showLearnedOverlay(
  BuildContext context, {
  required int amountMinor,
  required String title,
  required String body,
}) {
  final reduce = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => _Learned(
      amountMinor: amountMinor,
      title: title,
      body: body,
      reduceMotion: reduce,
    ),
    transitionBuilder: (context, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _Learned extends StatefulWidget {
  const _Learned({
    required this.amountMinor,
    required this.title,
    required this.body,
    required this.reduceMotion,
  });

  final int amountMinor;
  final String title;
  final String body;
  final bool reduceMotion;

  @override
  State<_Learned> createState() => _LearnedState();
}

class _LearnedState extends State<_Learned>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: widget.reduceMotion ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (!widget.reduceMotion) await _draw.forward();
    // Hold, longer when there's more to read.
    await Future<void>.delayed(
      Duration(milliseconds: widget.reduceMotion ? 1600 : 1400),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final curved = CurvedAnimation(parent: _draw, curve: Curves.easeOutCubic);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: c.surface1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: curved,
                  builder: (_, _) => Rosette(
                    size: 132,
                    color: c.ink(Bands.of(widget.amountMinor)),
                    strokeWidth: 0.9,
                    progress: curved.value,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  style: t.headline,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.body,
                  style: t.body.copyWith(color: c.text2),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
