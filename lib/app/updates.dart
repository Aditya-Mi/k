import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../ui/widgets/k_sheet.dart';

import '../data/backup/backup_service.dart';
import '../data/repositories/settings_repository.dart';
import '../data/update/update_service.dart';
import '../di.dart';
import '../platform/update_bridge.dart';
import '../ui/format.dart';
import '../ui/screens/backup/backup_screen.dart';
import '../ui/screens/settings/settings_parts.dart';
import '../ui/theme/k_theme.dart';

/// Device-local: the version code the owner said "Later" to, and when k
/// last checked.
const _skippedKey = 'device.update.skipped';
const _checkedKey = 'device.update.checkedAt';

/// Once per launch, after unlock: if a newer release is out (and not
/// skipped, unless it is required), show the update dialog (design 11).
Future<void> checkForUpdateOnLaunch(BuildContext context) async {
  final updates = getIt<UpdateService>();
  if (!updates.enabled) return;
  try {
    final check = await _check();
    if (!check.available || !context.mounted) return;
    final settings = getIt<SettingsRepository>();
    final skipped = await settings.getInt(_skippedKey);
    if (!check.required && skipped == check.manifest.versionCode) return;
    if (!context.mounted) return;
    await showUpdateDialog(context, check);
  } catch (_) {
    // Offline or the gist is unreachable: try again next launch.
  }
}

Future<UpdateCheck> _check() async {
  final installed = await getIt<UpdateBridge>().appVersion();
  final manifest = await getIt<UpdateService>().fetch();
  await getIt<SettingsRepository>().set(
    _checkedKey,
    DateTime.now().toIso8601String(),
  );
  return UpdateCheck(manifest, installedCode: installed.code);
}

Future<void> showUpdateDialog(BuildContext context, UpdateCheck check) =>
    showKDialog<void>(
      context: context,
      barrierDismissible: !check.required,
      builder: (_) => _UpdateDialog(check: check),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.check});

  final UpdateCheck check;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

/// Drive backup state when the dialog opened.
enum _Backup { unknown, on, off }

class _UpdateDialogState extends State<_UpdateDialog> {
  /// null = idle; else download progress (NaN while size unknown).
  double? _progress;
  String? _error;
  String? _installed;

  var _backup = _Backup.unknown;

  /// Backing up to Drive before the download (design 11b).
  var _backingUp = false;

  /// The backup failed (design 11c): "Couldn't back up…", Update anyway.
  String? _backupError;

  /// A backup this recent is copy enough; don't upload another.
  static const _freshBackup = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    getIt<UpdateBridge>().appVersion().then((v) {
      if (mounted) setState(() => _installed = v.name);
    });
    _loadBackup();
  }

  Future<void> _loadBackup() async {
    final backup = getIt<BackupService>();
    final on = await backup.driveAccount != null && await backup.hasPassphrase;
    if (mounted) setState(() => _backup = on ? _Backup.on : _Backup.off);
  }

  /// Before installing: a fresh Drive backup, so a bad update can be undone
  /// by restoring it (Android can't go back to an older version without
  /// uninstalling). Returns false when it failed and the owner must choose.
  Future<bool> _backUpFirst() async {
    final settings = getIt<SettingsRepository>();
    final last = DateTime.tryParse(
      await settings.get(BackupService.lastAt) ?? '',
    );
    if (last != null && DateTime.now().difference(last) < _freshBackup) {
      return true;
    }
    setState(() => _backingUp = true);
    try {
      await getIt<BackupService>().backupNow();
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _backupError = last == null
              ? "Couldn't back up to Drive. No earlier backup."
              : "Couldn't back up to Drive. Last backup: "
                    '${dayMonth(last)}, ${hhmm(last)}.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _turnOnBackup() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const BackupScreen()))
          .then((_) => _loadBackup());

  /// "Cancel" after a failed backup: back to the plain dialog, or closed
  /// when the update can wait.
  void _cancelAfterFailure() {
    if (widget.check.required) {
      setState(() => _backupError = null);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _update({bool skipBackup = false}) async {
    final bridge = getIt<UpdateBridge>();
    if (!await bridge.canInstall()) {
      if (!mounted) return;
      setState(
        () => _error =
            'Turn on Install unknown apps for k, then tap Update again.',
      );
      await bridge.openInstallSettings();
      return;
    }
    setState(() {
      _error = null;
      _backupError = null;
    });
    if (_backup == _Backup.unknown) await _loadBackup();
    if (!mounted) return;
    if (_backup == _Backup.on && !skipBackup && !await _backUpFirst()) {
      return;
    }
    if (!mounted) return;
    setState(() => _progress = double.nan);
    try {
      final file = await getIt<UpdateService>().download(
        widget.check.manifest,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p ?? double.nan);
        },
      );
      await bridge.install(file.path);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = "Couldn't download the update. Check the connection.";
        });
      }
    }
  }

  Future<void> _later() async {
    await getIt<SettingsRepository>().set(
      _skippedKey,
      '${widget.check.manifest.versionCode}',
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    final m = widget.check.manifest;
    final downloading = _progress != null;
    final busy = downloading || _backingUp;
    final mb = m.sizeBytes == 0
        ? ''
        : ' ${(m.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB.';
    return PopScope(
      canPop: !widget.check.required && !busy,
      child: KDialog(
        icon: Icon(Symbols.system_update_alt, color: c.text2),
        title: Text('k ${m.version} is ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.notes.trim().isNotEmpty) ...[
              Text(m.notes.trim(), style: t.body),
              const SizedBox(height: 12),
            ],
            Text(
              '${_installed == null ? '' : 'You have $_installed. '}'
              'Your payments and settings stay.'
              '$mb${widget.check.required ? ' This version is required.' : ''}',
              style: t.meta.copyWith(color: c.text2),
            ),
            if (_backup == _Backup.off && !busy) ...[
              const SizedBox(height: 12),
              Text(
                "Backup is off, so there's no copy to go back to.",
                style: t.meta.copyWith(color: c.text2),
              ),
              // In the content, not the actions: three actions don't fit
              // one row on a phone-width dialog.
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _turnOnBackup,
                child: const Text('Turn on backup'),
              ),
            ],
            if (_backingUp) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                color: c.text,
                backgroundColor: c.surface3,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              Text('Backing up to Drive first…', style: t.meta),
            ],
            if (_backupError != null) ...[
              const SizedBox(height: 12),
              Text(_backupError!, style: t.meta.copyWith(color: c.alert)),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress!.isNaN ? null : _progress,
                color: c.text,
                backgroundColor: c.surface3,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              Text(
                _progress!.isNaN
                    ? 'Downloading…'
                    : 'Downloading · ${(_progress! * 100).round()}%',
                style: t.meta,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: t.meta.copyWith(color: c.alert)),
            ],
          ],
        ),
        actions: busy
            ? const []
            : _backupError != null
            ? [
                TextButton(
                  onPressed: _cancelAfterFailure,
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => _update(skipBackup: true),
                  child: const Text('Update anyway'),
                ),
              ]
            : [
                if (!widget.check.required)
                  TextButton(onPressed: _later, child: const Text('Later')),
                FilledButton(
                  onPressed: _update,
                  child: Text(_error == null ? 'Update' : 'Try again'),
                ),
              ],
      ),
    );
  }
}

/// Settings → About (design 06): version, last check, manual check.
class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  String? _version;
  var _checking = false;

  @override
  void initState() {
    super.initState();
    getIt<UpdateBridge>().appVersion().then((v) {
      if (mounted) setState(() => _version = v.name);
    });
  }

  Future<void> _checkNow() async {
    if (!getIt<UpdateService>().enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This build does not check for updates')),
      );
      return;
    }
    setState(() => _checking = true);
    try {
      final check = await _check();
      if (!mounted) return;
      if (check.available) {
        await showUpdateDialog(context, check);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('k is up to date')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't reach GitHub. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SettingsHead('About'),
      StreamBuilder<DateTime?>(
        stream: getIt<SettingsRepository>().watchDate(_checkedKey),
        builder: (context, snap) {
          final at = snap.data;
          return SettingsItem(
            icon: Symbols.info,
            title: 'k ${_version ?? ''}',
            subtitle: at == null
                ? 'Not checked for updates yet'
                : 'Checked for updates ${dayMonth(at)}, ${hhmm(at)}',
          );
        },
      ),
      SettingsItem(
        icon: Symbols.system_update_alt,
        title: 'Check for updates',
        subtitle: 'Also checked when k opens',
        onTap: _checking ? null : _checkNow,
        trailing: _checking
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
    ],
  );
}
