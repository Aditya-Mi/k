import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/backup/backup_service.dart';
import '../data/email/email_sync.dart';
import '../data/ingest/ingestion_service.dart';
import '../data/ingest/sms_sync.dart';
import '../data/ingest/transfer_linker.dart';
import '../data/repositories/settings_repository.dart';
import '../data/subscriptions/subscription_service.dart';
import '../platform/sms_bridge.dart';
import 'notifications.dart';

/// Keeps the ledger fed while the UI runs: drains the live queue on every
/// receiver event, and on start/resume also catches up from the inbox.
/// Subscriptions are re-matched after every pass.
class SmsController with WidgetsBindingObserver {
  SmsController(
    this._sync,
    this._bridge,
    this._settings,
    this._transfers,
    this._subscriptions,
    this._ingestion,
    this._notifications,
    this._email,
    this._backup,
  );

  final SmsSync _sync;
  final TransferLinker _transfers;
  final SmsBridge _bridge;
  final SettingsRepository _settings;
  final SubscriptionService _subscriptions;
  final IngestionService _ingestion;
  final KNotifications _notifications;
  final EmailSync _email;
  final BackupService _backup;

  /// Null until first checked.
  final smsGranted = ValueNotifier<bool?>(null);
  StreamSubscription<void>? _events;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _notifications.appVisible = true;
    unawaited(_notifications.clearReview());
    _events = _bridge.onPending.listen(
      (_) => _guard(_sync.drainPending).then((_) => _refreshSubscriptions()),
    );
    // Pairs transfers logged before linking existed (and any missed pairs).
    // Review items get another read: a newer parser may know them now.
    unawaited(
      _guard(_transfers.autoLinkAll)
          .then((_) => _guard(_transfers.markCardBillsAll))
          .then((_) => _guard(_ingestion.reprocessReview))
          .then((_) => refresh()),
    );
  }

  Future<void> refresh() async {
    final granted = await Permission.sms.isGranted;
    smsGranted.value = granted;
    if (!await _settings.getBool(SettingsRepository.onboardingDone)) return;
    // The queue was captured while permission was held; drain regardless.
    await _guard(_sync.drainPending);
    if (granted) await _guard(_sync.catchUp);
    await _refreshEmail();
    await _refreshSubscriptions();
    await _refreshBackup();
  }

  /// Keeps the daily worker in step; catches up when it fell behind.
  Future<void> _refreshBackup() async {
    try {
      await _backup.refresh();
    } catch (e, s) {
      debugPrint('k: backup refresh failed: $e\n$s');
    }
  }

  /// Keeps the hourly worker matching the inbox list, and tops up on open.
  Future<void> _refreshEmail() async {
    try {
      final on = await _email.hasAccounts;
      await _bridge.scheduleEmailSync(on: on);
      if (on) await _email.syncIfStale(const Duration(minutes: 30));
    } catch (e, s) {
      debugPrint('k: email refresh failed: $e\n$s');
    }
  }

  Future<void> _refreshSubscriptions() async {
    try {
      await _subscriptions.refresh();
    } catch (e, s) {
      debugPrint('k: subscription refresh failed: $e\n$s');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    _notifications.appVisible = visible;
    if (visible) {
      unawaited(_notifications.clearReview());
      unawaited(refresh());
    }
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
