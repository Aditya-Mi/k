import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/notifications.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../subscriptions/subscription_parts.dart';

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
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          title: _permission == null ? '…' : (allowed ? 'Allowed' : 'Off'),
          subtitle: allowed
              ? 'Android notification permission for k'
              : 'Tap to allow. Nothing below can show until you do.',
          onTap: allowed ? openAppSettings : _allow,
          trailing: const _Chevron(),
        ),
        StreamBuilder<String?>(
          stream: _settings.watch(SubscriptionService.reminderKey),
          builder: (context, snap) {
            final days = int.tryParse(snap.data ?? '') ?? 3;
            return SettingsItem(
              icon: Icons.notifications_outlined,
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
          icon: Icons.rule_rounded,
          title: 'Needs review',
          subtitle: "When a bank message couldn't be read",
        ),
        _Toggle(
          settingKey: KNotifications.paymentsKey,
          icon: Icons.receipt_long_outlined,
          title: 'Payment logged',
          subtitle:
              'Each payment as its SMS arrives. Amounts stay hidden on the '
              'lock screen.',
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
      Icon(Icons.chevron_right_rounded, size: 20, color: context.k.text3);
}

/// Section label in the design 06 style.
class SettingsHead extends StatelessWidget {
  const SettingsHead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(
      text,
      style: context.kt.meta.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Icon, title over subtitle, trailing control (design 06 items).
class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: c.text2),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.body.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: t.meta.copyWith(fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
      ),
    );
  }
}
