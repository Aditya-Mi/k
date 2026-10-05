import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import '../../../data/backup/backup_service.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../backup/backup_parts.dart';
import '../backup/backup_screen.dart';
import '../backup/export_sheet.dart';
import 'settings_parts.dart';

/// Settings → Backup (design 06): Drive backup switch (row opens 06e) and
/// Export (06h).
class BackupSettings extends StatefulWidget {
  const BackupSettings({super.key});

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  final _settings = getIt<SettingsRepository>();
  late final Stream<(String?, DateTime?, String?)> _state = Rx.combineLatest3(
    _settings.watch(BackupService.account),
    _settings.watchDate(BackupService.lastAt),
    _settings.watch(BackupService.error),
    (a, at, e) => (a, at, e == null || e.isEmpty ? null : e),
  );
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        await turnOnBackup(context);
      } else {
        await getIt<BackupService>().turnOff();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return StreamBuilder<(String?, DateTime?, String?)>(
      stream: _state,
      builder: (context, snap) {
        final (account, lastAt, error) = snap.data ?? (null, null, null);
        final on = account != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsHead('Backup'),
            SettingsItem(
              icon: error == null
                  ? Icons.cloud_upload_outlined
                  : Icons.cloud_off_outlined,
              iconColor: error == null ? null : c.alert,
              title: 'Google Drive backup',
              subtitle: !on
                  ? 'Off'
                  : error ??
                        [
                          'Daily, encrypted',
                          if (lastAt != null) 'last ${whenShort(lastAt)}',
                          'keeps ${BackupService.keep}',
                        ].join(' · '),
              subtitleColor: error == null ? null : c.alert,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
              ),
              trailing: Switch(value: on, onChanged: _busy ? null : _toggle),
            ),
            SettingsItem(
              icon: Icons.download_rounded,
              title: 'Export',
              subtitle: 'CSV or encrypted backup file',
              onTap: () => showExportSheet(context),
              trailing: const SettingsChevron(),
            ),
          ],
        );
      },
    );
  }
}
