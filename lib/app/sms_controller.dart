import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/ingest/sms_sync.dart';
import '../data/repositories/settings_repository.dart';
import '../platform/sms_bridge.dart';

/// Keeps the ledger fed while the UI runs: drains the live queue on every
/// receiver event, and on start/resume also catches up from the inbox.
class SmsController with WidgetsBindingObserver {
  SmsController(this._sync, this._bridge, this._settings);

  final SmsSync _sync;
  final SmsBridge _bridge;
  final SettingsRepository _settings;

  /// Null until first checked.
  final smsGranted = ValueNotifier<bool?>(null);
  StreamSubscription<void>? _events;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _events = _bridge.onPending.listen((_) => _guard(_sync.drainPending));
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final granted = await Permission.sms.isGranted;
    smsGranted.value = granted;
    if (!await _settings.getBool(SettingsRepository.onboardingDone)) return;
    // The queue was captured while permission was held; drain regardless.
    await _guard(_sync.drainPending);
    if (granted) await _guard(_sync.catchUp);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> _guard(Future<int> Function() run) async {
    try {
      await run();
    } catch (e, s) {
      debugPrint('k: SMS sync failed: $e\n$s');
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    smsGranted.dispose();
  }
}
