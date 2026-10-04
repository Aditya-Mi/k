import 'package:flutter/material.dart';

import '../data/ingest/sms_sync.dart';
import '../data/repositories/settings_repository.dart';
import '../di.dart';
import '../platform/sms_bridge.dart';
import '../ui/screens/home_shell.dart';
import '../ui/screens/onboarding/onboarding_screen.dart';
import '../ui/theme/k_theme.dart';
import 'sms_controller.dart';

class KApp extends StatefulWidget {
  const KApp({super.key, required this.onboarded});

  final bool onboarded;

  @override
  State<KApp> createState() => _KAppState();
}

class _KAppState extends State<KApp> {
  late bool _onboarded = widget.onboarded;
  late final SmsController _sms = SmsController(
    getIt<SmsSync>(),
    getIt<SmsBridge>(),
    getIt<SettingsRepository>(),
  )..start();

  @override
  void dispose() {
    _sms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'k',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: _onboarded
        ? HomeShell(sms: _sms)
        : OnboardingScreen(
            onDone: () {
              setState(() => _onboarded = true);
              _sms.refresh();
            },
          ),
  );
}
