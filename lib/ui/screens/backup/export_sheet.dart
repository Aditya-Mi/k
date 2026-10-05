import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../data/backup/backup_service.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../settings/settings_parts.dart';
import 'passphrase_screen.dart';

/// Export (design 06h): payments as CSV, or the encrypted backup file;
/// either is saved where the owner picks (Android's save dialog).
Future<void> showExportSheet(BuildContext context) async {
  final pick = await showModalBottomSheet<_Kind>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final t = context.kt;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Export', style: t.title),
                  const SizedBox(height: 2),
                  Text('Saved to a folder you pick', style: t.meta),
                ],
              ),
            ),
            SettingsItem(
              icon: Icons.table_view_outlined,
              title: 'Payments as CSV',
              subtitle: 'Every payment. Not encrypted: anyone with the file can read it.',
              onTap: () => Navigator.pop(context, _Kind.csv),
            ),
            SettingsItem(
              icon: Icons.lock_outline_rounded,
              title: 'Backup file',
              subtitle: 'Everything, encrypted with your backup passphrase',
              onTap: () => Navigator.pop(context, _Kind.backup),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (pick == null || !context.mounted) return;
  final backup = getIt<BackupService>();
  final messenger = ScaffoldMessenger.of(context);
  if (pick == _Kind.backup && !await backup.hasPassphrase) {
    if (!context.mounted) return;
    final set = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PassphraseScreen(action: 'Save passphrase'),
      ),
    );
    if (set != true) return;
  }
  try {
    final (Uint8List bytes, String name) = pick == _Kind.csv
        ? await backup.exportCsv()
        : await backup.exportFile();
    final saved = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: pick == _Kind.csv ? 'text/csv' : 'application/octet-stream',
    );
    if (saved != null) {
      messenger.showSnackBar(SnackBar(content: Text('Saved $name')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't export: $e")));
  }
}

enum _Kind { csv, backup }
