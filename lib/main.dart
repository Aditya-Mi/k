import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_lock.dart';
import 'app/notifications.dart';
import 'data/backup/backup_service.dart';
import 'data/db/app_database.dart';
import 'data/email/email_sync.dart';
import 'data/ingest/sms_sync.dart';
import 'data/repositories/settings_repository.dart';
import 'di.dart';
import 'platform/sms_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  try {
    await getIt<KNotifications>().init();
  } catch (e, s) {
    // Reminders off for this run; the app itself must still open.
    debugPrint('k: reminders unavailable: $e\n$s');
  }
  final onboarded = await getIt<SettingsRepository>().getBool(
    SettingsRepository.onboardingDone,
  );
  final settings = getIt<SettingsRepository>();
  final theme = await settings.get(SettingsRepository.themeMode);
  final lock = AppLock(
    settings,
    enabled: await settings.getBool(SettingsRepository.appLock),
  );
  getIt.registerSingleton<AppLock>(lock);
  runApp(KApp(onboarded: onboarded, lock: lock, theme: theme));
}

/// Headless entrypoint run by the native `SmsProcessWorker` when an SMS
/// arrives while the app is closed: store queued SMS, then report back.
@pragma('vm:entry-point')
Future<void> smsBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final bridge = SmsBridge();
  var ok = false;
  try {
    await configureDependencies();
    try {
      await getIt<KNotifications>().init();
    } catch (e) {
      debugPrint('k: notifications unavailable in background: $e');
    }
    final logged = await getIt<SmsSync>().drainPending();
    // Count only, never content. tool/smoke_test.sh waits for this line.
    debugPrint('k: background SMS drained, logged $logged');
    ok = true;
  } catch (e, s) {
    debugPrint('k: background SMS ingest failed: $e\n$s');
  } finally {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await bridge.backgroundDone(ok: ok);
  }
}

/// Headless entrypoint run hourly by the native `EmailSyncWorker`: read new
/// bank mail from every connected inbox, then report back.
@pragma('vm:entry-point')
Future<void> emailBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final bridge = SmsBridge();
  var ok = false;
  try {
    await configureDependencies();
    try {
      await getIt<KNotifications>().init();
    } catch (e) {
      debugPrint('k: notifications unavailable in background: $e');
    }
    await getIt<EmailSync>().syncAll();
    await getIt<SettingsRepository>().set(
      EmailSync.backgroundAtKey,
      DateTime.now().toIso8601String(),
    );
    ok = true;
  } catch (e, s) {
    debugPrint('k: background email sync failed: $e\n$s');
  } finally {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await bridge.backgroundDone(ok: ok);
  }
}

/// Headless entrypoint run daily by the native `BackupWorker`: seal the
/// database and upload it to Drive, then report back.
@pragma('vm:entry-point')
Future<void> backupBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final bridge = SmsBridge();
  var ok = false;
  try {
    await configureDependencies();
    await getIt<BackupService>().runIfDue();
    ok = true;
  } catch (e, s) {
    debugPrint('k: background backup failed: $e\n$s');
  } finally {
    if (getIt.isRegistered<AppDatabase>()) {
      await getIt<AppDatabase>().close();
    }
    await bridge.backgroundDone(ok: ok);
  }
}
