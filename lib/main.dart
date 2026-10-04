import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/reminder_scheduler.dart';
import 'data/db/app_database.dart';
import 'data/ingest/sms_sync.dart';
import 'data/repositories/settings_repository.dart';
import 'di.dart';
import 'platform/sms_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  try {
    await getIt<ReminderScheduler>().init();
  } catch (e, s) {
    // Reminders off for this run; the app itself must still open.
    debugPrint('k: reminders unavailable: $e\n$s');
  }
  final onboarded = await getIt<SettingsRepository>().getBool(
    SettingsRepository.onboardingDone,
  );
  runApp(KApp(onboarded: onboarded));
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
    await getIt<SmsSync>().drainPending();
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
