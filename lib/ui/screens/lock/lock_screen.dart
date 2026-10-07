import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/app_lock.dart';
import '../../theme/k_theme.dart';
import '../../widgets/rosette.dart';

/// Lock screen (design 07): the locked month panel (no total, neutral
/// rosette), "k is locked" and Unlock. The system BiometricPrompt draws
/// itself over this (07b). On success the rosette draws itself, holds, and
/// the screen fades into home (DESIGN.md Motion).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});

  final AppLock lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: 1,
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  late final AppLifecycleListener _lifecycle;
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    // Ask straight away while k is in front; on resume too, when the lock
    // came back after time away.
    _lifecycle = AppLifecycleListener(onResume: _autoAsk);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoAsk());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _autoAsk() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _unlock();
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    final r = await widget.lock.unlock();
    if (!mounted) return;
    switch (r) {
      case UnlockResult.ok || UnlockResult.unavailable:
        await _opened();
      case UnlockResult.lockedOut:
        setState(() => _note = 'Too many tries. Wait a moment, then unlock.');
      case UnlockResult.failed:
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The drawn moment: 600ms draw, 400ms hold, 200ms fade into home.
  Future<void> _opened() async {
    if (!MediaQuery.of(context).disableAnimations) {
      _draw.value = 0;
      await _draw.forward();
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await _fade.reverse();
    widget.lock.release();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final curved = CurvedAnimation(parent: _draw, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: _fade,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _LockedPanel(
                    rosette: AnimatedBuilder(
                      animation: curved,
                      builder: (_, _) => LayoutBuilder(
                        builder: (context, box) => Rosette(
                          size: box.maxHeight,
                          color: c.text3,
                          strokeWidth: 0.5,
                          progress: curved.value,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text('k is locked', style: t.headline),
                const SizedBox(height: 8),
                Text(
                  _note ?? 'Your fingerprint or screen lock opens it',
                  style: t.body.copyWith(
                    color: _note == null ? c.text2 : c.alert,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _unlock,
                    icon: const Icon(Symbols.lock_open),
                    label: const Text('Unlock'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The month panel's locked twin: wordmark, hidden total, neutral rosette.
class _LockedPanel extends StatelessWidget {
  const _LockedPanel({required this.rosette});

  final Widget rosette;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AspectRatio(
        aspectRatio: 2.2,
        child: Stack(
          children: [
            Positioned(
              top: 5,
              right: 12,
              bottom: 5,
              child: AspectRatio(aspectRatio: 1, child: rosette),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('k', style: t.wordmark),
                  const Spacer(),
                  Semantics(
                    label: 'Total hidden',
                    child: ExcludeSemantics(
                      child: Text(
                        '₹ ••,•••',
                        style: t.title.copyWith(
                          color: c.text3,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
