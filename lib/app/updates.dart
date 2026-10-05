import 'package:flutter/material.dart';

import '../data/repositories/settings_repository.dart';
import '../data/update/update_service.dart';
import '../di.dart';
import '../platform/update_bridge.dart';
import '../ui/format.dart';
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
    showDialog<void>(
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

class _UpdateDialogState extends State<_UpdateDialog> {
  /// null = idle; else download progress (NaN while size unknown).
  double? _progress;
  String? _error;
  String? _installed;

  @override
  void initState() {
    super.initState();
    getIt<UpdateBridge>().appVersion().then((v) {
      if (mounted) setState(() => _installed = v.name);
    });
  }

  Future<void> _update() async {
    final bridge = getIt<UpdateBridge>();
    if (!await bridge.canInstall()) {
      if (!mounted) return;
      setState(
        () => _error =
            'Allow k to install apps: tap Update again after turning on '
            'Install unknown apps for k.',
      );
      await bridge.openInstallSettings();
      return;
    }
    setState(() {
      _progress = double.nan;
      _error = null;
    });
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
          _error =
              "Couldn't download the update. Check the connection and "
              'try again.';
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
    final mb = m.sizeBytes == 0
        ? ''
        : ' ${(m.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB from GitHub.';
    return PopScope(
      canPop: !widget.check.required && !downloading,
      child: AlertDialog(
        icon: Icon(Icons.system_update_alt_rounded, color: c.text2),
        title: Text('k ${m.version} is ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.notes.trim().isNotEmpty) ...[
              Text(m.notes.trim(), style: t.body.copyWith(fontSize: 14.5)),
              const SizedBox(height: 12),
            ],
            Text(
              '${_installed == null ? '' : 'You have $_installed. '}'
              'It installs over this one; your payments and settings stay.'
              '$mb${widget.check.required ? ' This version is required.' : ''}',
              style: t.meta.copyWith(fontSize: 13, color: c.text2),
            ),
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
        actions: downloading
            ? const []
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
            icon: Icons.info_outline_rounded,
            title: 'k ${_version ?? ''}',
            subtitle: at == null
                ? 'Not checked for updates yet'
                : 'Checked for updates ${dayMonth(at)}, ${hhmm(at)}',
          );
        },
      ),
      SettingsItem(
        icon: Icons.system_update_alt_rounded,
        title: 'Check for updates',
        subtitle:
            'k also checks when it opens. Updates come from '
            'github.com/Aditya-Mi/k',
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
