import 'package:flutter/material.dart';

import '../../../data/db/enums.dart';
import '../../../data/email/email_sync.dart';
import '../../../di.dart';
import '../../../platform/sms_bridge.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import 'connect_inbox_screen.dart';
import 'settings_parts.dart';

/// Settings → Email (design 06 / 06d): connected inboxes, their last check
/// or failure, and connecting another.
class EmailSettings extends StatelessWidget {
  const EmailSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return StreamBuilder<List<EmailAccountView>>(
      stream: getIt<EmailSync>().watch(),
      builder: (context, snap) {
        final inboxes = snap.data ?? const <EmailAccountView>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsHead('Email'),
            for (final a in inboxes)
              SettingsItem(
                icon: a.error == null
                    ? Icons.mail_outline_rounded
                    : Icons.error_outline_rounded,
                iconColor: a.error == null ? null : c.alert,
                title: a.row.email,
                subtitle: a.error == null
                    ? '${_method(a)} · ${_checked(a)}'
                    : 'Sign-in failed · tap to fix',
                subtitleColor: a.error == null ? null : c.alert,
                onTap: () => _inboxSheet(context, a),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: c.text3,
                ),
              ),
            SettingsItem(
              icon: Icons.add_rounded,
              title: inboxes.isEmpty
                  ? 'Connect an inbox'
                  : 'Connect another inbox',
              subtitle: 'Bank alert emails, merged with their SMS',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const ConnectInboxScreen(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _method(EmailAccountView a) =>
      a.row.authType == EmailAuthType.oauth ? 'Gmail sign-in' : 'App password';

  static String _checked(EmailAccountView a) {
    final at = a.row.lastSyncAt;
    if (at == null) return 'not checked yet';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return at.isAfter(today)
        ? 'checked ${hhmm(at)}'
        : 'checked ${dayMonth(at)}, ${hhmm(at)}';
  }

  Future<void> _inboxSheet(BuildContext context, EmailAccountView a) async {
    final sync = getIt<EmailSync>();
    final t = context.kt;
    final c = context.k;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.row.email, style: t.title),
                  const SizedBox(height: 2),
                  Text(
                    a.error ?? '${_method(a)} · ${_checked(a)}',
                    style: t.meta.copyWith(
                      fontSize: 13,
                      color: a.error == null ? null : c.alert,
                    ),
                  ),
                ],
              ),
            ),
            if (a.row.authType == EmailAuthType.imap)
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Enter a new app password'),
                onTap: () => Navigator.pop(context, 'password'),
              ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Check now'),
              onTap: () => Navigator.pop(context, 'check'),
            ),
            ListTile(
              leading: const Icon(Icons.link_off_rounded),
              title: const Text('Disconnect'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'password':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AppPasswordScreen(email: a.row.email),
          ),
        );
      case 'check':
        final n = await sync.syncAll();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                n == 0
                    ? 'Up to date'
                    : '$n new ${n == 1 ? 'payment' : 'payments'} logged',
              ),
            ),
          );
        }
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Disconnect ${a.row.email}?'),
            content: const Text(
              'k stops reading this inbox and forgets its password. Payments '
              'already logged stay.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await sync.remove(a.row.id);
          await getIt<SmsBridge>().scheduleEmailSync(
            on: await sync.hasAccounts,
          );
        }
    }
  }
}
