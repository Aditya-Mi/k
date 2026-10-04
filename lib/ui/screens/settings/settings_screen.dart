import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/ingest/sms_sync.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/date_pick.dart';
import '../../../data/review/learned_formats.dart';
import '../review/learned_formats_screen.dart';
import 'appearance_settings.dart';
import 'email_settings.dart';
import 'notification_settings.dart';

/// Phase 2 settings: SMS capture health only. Banks, Gmail, backup and app
/// lock arrive in later phases.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PermissionStatus? _sms;
  PermissionStatus? _battery;
  bool _checking = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final sms = await Permission.sms.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    if (!mounted) return;
    setState(() {
      _sms = sms;
      _battery = battery;
    });
  }

  Future<void> _fixSms() async {
    final status = await Permission.sms.request();
    if (!status.isGranted) await openAppSettings();
    await _refresh();
  }

  Future<void> _checkNow() {
    final sync = getIt<SmsSync>();
    return _run(() async => await sync.drainPending() + await sync.catchUp());
  }

  /// Backfill from a chosen day. Already-logged messages are skipped.
  Future<void> _importOlder() async {
    final day = await pickImportStart(context);
    if (day == null || !mounted) return;
    await _run(() => getIt<SmsSync>().importHistory(day));
  }

  Future<void> _run(Future<int> Function() job) async {
    setState(() => _checking = true);
    var logged = 0;
    try {
      logged = await job();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          logged == 0
              ? 'Up to date'
              : '$logged new ${logged == 1 ? 'payment' : 'payments'} logged',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final smsOk = _sms?.isGranted ?? false;
    final batteryOk = _battery?.isGranted ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text('Bank SMS', style: t.title),
                const SizedBox(height: 4),
                FieldRow(
                  label: 'SMS access',
                  onTap: smsOk ? null : _fixSms,
                  value: Text(
                    _sms == null ? '…' : (smsOk ? 'On' : 'Off · tap to fix'),
                    style: t.body,
                  ),
                ),
                if (_sms?.isPermanentlyDenied ?? false)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'If Android will not show the prompt: App info → ⋮ → Allow '
                      'restricted settings, then Permissions → SMS → Allow.',
                      style: t.meta,
                    ),
                  ),
                FieldRow(
                  label: 'Battery limits',
                  onTap: batteryOk
                      ? null
                      : () async {
                          await Permission.ignoreBatteryOptimizations.request();
                          await _refresh();
                        },
                  value: Text(
                    _battery == null
                        ? '…'
                        : (batteryOk ? 'Unrestricted' : 'Limited · tap to fix'),
                    style: t.body,
                  ),
                ),
                StreamBuilder<DateTime?>(
                  stream: getIt<SettingsRepository>().watchDate(
                    SettingsRepository.smsLastSyncAt,
                  ),
                  builder: (context, snap) => FieldRow(
                    label: 'Last checked',
                    value: Text(
                      snap.data == null
                          ? 'Never'
                          : '${dayMonth(snap.data!)}, ${hhmm(snap.data!)}',
                      style: t.body,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _checking || !smsOk ? null : _checkNow,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Check inbox now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _checking || !smsOk ? null : _importOlder,
                      icon: const Icon(Icons.history_rounded, size: 20),
                      label: const Text('Import older messages'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Design 06 items run edge to edge.
          const EmailSettings(),
          const NotificationSettings(),
          const AppearanceSettings(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text('Message formats', style: t.title),
                const SizedBox(height: 4),
                StreamBuilder<List<LearnedFormat>>(
                  stream: getIt<LearnedFormats>().watch(),
                  builder: (context, snap) => FieldRow(
                    label: 'Learned in Review',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const LearnedFormatsScreen(),
                      ),
                    ),
                    value: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snap.data == null ? '…' : '${snap.data!.length}',
                          style: t.body,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: c.text2),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Messages are read on this phone and stored encrypted. Nothing is '
                  'sent anywhere.',
                  style: t.meta.copyWith(color: c.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
