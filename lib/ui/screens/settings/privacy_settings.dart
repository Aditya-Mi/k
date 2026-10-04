import 'package:flutter/material.dart';

import '../../../app/app_lock.dart';
import '../../../di.dart';
import 'settings_parts.dart';

/// Settings → Privacy (design 06): app lock on/off. Turning it on asks the
/// system prompt once, so it can't lock the owner out.
class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lock = getIt<AppLock>();
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) {
        Future<void> set(bool on) async {
          if (!on) return lock.disable();
          final r = await lock.enable();
          if (!context.mounted || r == UnlockResult.ok) return;
          final msg = switch (r) {
            UnlockResult.unavailable => 'Set a screen lock on the phone first (Android Settings → Security).',
            UnlockResult.lockedOut => 'Too many tries. Try again in a moment.',
            _ => 'App lock stays off.',
          };
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsHead('Privacy'),
            SettingsItem(
              icon: Icons.fingerprint_rounded,
              title: 'App lock',
              subtitle: 'Fingerprint or device PIN when k opens',
              onTap: () => set(!lock.enabled),
              trailing: Switch(value: lock.enabled, onChanged: set),
            ),
          ],
        );
      },
    );
  }
}
