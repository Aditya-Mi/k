import 'package:flutter/material.dart';

import '../data/email/email_sync.dart';
import '../data/ingest/ingestion_service.dart';
import '../data/ingest/sms_sync.dart';
import '../data/ingest/transfer_linker.dart';
import '../data/repositories/settings_repository.dart';
import '../data/subscriptions/subscription_service.dart';
import '../di.dart';
import '../platform/sms_bridge.dart';
import '../ui/screens/home_shell.dart';
import '../ui/screens/lock/lock_screen.dart';
import '../ui/screens/onboarding/onboarding_screen.dart';
import '../ui/theme/k_theme.dart';
import 'app_lock.dart';
import 'notifications.dart';
import 'sms_controller.dart';

class KApp extends StatefulWidget {
  const KApp({
    super.key,
    required this.onboarded,
    required this.lock,
    this.theme,
  });

  final bool onboarded;
  final AppLock lock;

  /// Saved theme mode name, read before the first frame (no flash).
  final String? theme;

  @override
  State<KApp> createState() => _KAppState();
}

class _KAppState extends State<KApp> {
  late bool _onboarded = widget.onboarded;
  late final SmsController _sms = SmsController(
    getIt<SmsSync>(),
    getIt<SmsBridge>(),
    getIt<SettingsRepository>(),
    getIt<TransferLinker>(),
    getIt<SubscriptionService>(),
    getIt<IngestionService>(),
    getIt<KNotifications>(),
    getIt<EmailSync>(),
  )..start();

  @override
  void dispose() {
    _sms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: getIt<SettingsRepository>().watch(SettingsRepository.themeMode),
    initialData: widget.theme,
    builder: (context, snap) => MaterialApp(
      title: 'k',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.values.asNameMap()[snap.data] ?? ThemeMode.system,
      // Above the navigator, so every route (and a notification tap) sits
      // behind the lock.
      builder: (context, child) => ListenableBuilder(
        listenable: widget.lock,
        builder: (context, _) {
          final locked = _onboarded && widget.lock.locked;
          return Stack(
            children: [
              ExcludeSemantics(
                excluding: locked,
                child: TickerMode(enabled: !locked, child: child!),
              ),
              if (locked) LockScreen(lock: widget.lock),
            ],
          );
        },
      ),
      home: _onboarded
          ? HomeShell(sms: _sms)
          : OnboardingScreen(
              onDone: () {
                setState(() => _onboarded = true);
                _sms.refresh();
              },
            ),
    ),
  );
}
