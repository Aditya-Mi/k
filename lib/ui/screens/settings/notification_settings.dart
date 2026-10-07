import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/notifications.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../subscriptions/subscription_parts.dart';
import 'settings_parts.dart';

/// Settings → Notifications (design 06): permission, reminder timing, and
/// on/off for the two live alerts.
class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  PermissionStatus? _permission;
  late final AppLifecycleListener _lifecycle;
  final _settings = getIt<SettingsRepository>();

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
    final p = await Permission.notification.status;
    if (mounted) setState(() => _permission = p);
  }

  Future<void> _allow() async {
    final p = await Permission.notification.request();
    if (!p.isGranted) await openAppSettings();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _permission?.isGranted ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHead('Notifications'),
        SettingsItem(
          icon: allowed
              ? Symbols.notifications_active
              : Symbols.notifications_off,
          title: _permission == null ? '…' : (allowed ? 'Allowed' : 'Off'),
          subtitle: allowed ? 'Android permission is on' : 'Tap to allow',
          onTap: allowed ? openAppSettings : _allow,
          trailing: const _Chevron(),
        ),
        StreamBuilder<String?>(
          stream: _settings.watch(SubscriptionService.reminderKey),
          builder: (context, snap) {
            final days = int.tryParse(snap.data ?? '') ?? 3;
            return SettingsItem(
              icon: Symbols.notifications,
              title: 'Subscription reminders',
              subtitle: days == 0
                  ? 'Off'
                  : '${reminderLabel(days).replaceFirst(' before', '')} '
                        'before each charge',
              onTap: () async {
                final d = await pickReminder(context, current: days);
                if (d != null && d >= 0) {
                  await getIt<SubscriptionService>().setDefaultReminder(d);
                }
              },
              trailing: const _Chevron(),
            );
          },
        ),
        _Toggle(
          settingKey: KNotifications.reviewKey,
          icon: Symbols.rule,
          title: 'Needs review',
          subtitle: "When a bank message couldn't be read",
        ),
        _Toggle(
          settingKey: KNotifications.paymentsKey,
          icon: Symbols.receipt_long,
          title: 'Payment logged',
          subtitle: 'Amounts are hidden on the lock screen',
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.settingKey,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String settingKey;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final settings = getIt<SettingsRepository>();
    return StreamBuilder<String?>(
      stream: settings.watch(settingKey),
      builder: (context, snap) {
        final on = snap.data != 'false';
        void set(bool v) => settings.set(settingKey, '$v');
        return SettingsItem(
          icon: icon,
          title: title,
          subtitle: subtitle,
          onTap: () => set(!on),
          trailing: Switch(value: on, onChanged: set),
        );
      },
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) =>
      Icon(Symbols.chevron_right, size: 20, color: context.k.text3);
}
