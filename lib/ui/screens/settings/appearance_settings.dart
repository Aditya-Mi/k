import 'package:flutter/material.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import 'settings_parts.dart';

/// Settings → Appearance (design 06): follow the phone, or always light or
/// dark. Device-local, applied app-wide by `KApp`.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key, this.showHead = true});

  /// Off when grouped under another head (Settings → This phone).
  final bool showHead;

  static const _labels = {
    ThemeMode.system: 'Same as the phone',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    final settings = getIt<SettingsRepository>();
    final c = context.k;
    return StreamBuilder<String?>(
      stream: settings.watch(SettingsRepository.themeMode),
      builder: (context, snap) {
        final mode =
            ThemeMode.values.asNameMap()[snap.data] ?? ThemeMode.system;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHead) const SettingsHead('Appearance'),
            SettingsItem(
              icon: Icons.contrast_rounded,
              title: 'Theme',
              subtitle: _labels[mode]!,
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: c.text3,
              ),
              onTap: () async {
                final picked = await showModalBottomSheet<ThemeMode>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Theme', style: context.kt.title),
                          ),
                        ),
                        for (final m in _labels.keys)
                          ListTile(
                            title: Text(_labels[m]!),
                            trailing: m == mode
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => Navigator.pop(context, m),
                          ),
                      ],
                    ),
                  ),
                );
                if (picked != null) {
                  await settings.set(SettingsRepository.themeMode, picked.name);
                }
              },
            ),
          ],
        );
      },
    );
  }
}
