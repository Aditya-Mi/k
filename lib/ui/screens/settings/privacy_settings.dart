import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/app_lock.dart';
import '../../../di.dart';
import 'settings_parts.dart';

/// Settings → Privacy (design 06): app lock on/off. Turning it on asks the
/// system prompt once, so it can't lock the owner out.
class PrivacySettings extends StatelessWidget {
  const PrivacySettings({super.key, this.showHead = true});

  /// Off when grouped under another head (Settings → This phone).
  final bool showHead;

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
            UnlockResult.unavailable =>
              'Set a screen lock in Android Settings first.',
            UnlockResult.lockedOut => 'Too many tries. Try again in a moment.',
            _ => 'App lock stays off.',
          };
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHead) const SettingsHead('Privacy'),
            SettingsItem(
              icon: Symbols.fingerprint,
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
