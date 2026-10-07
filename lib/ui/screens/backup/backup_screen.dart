import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rxdart/rxdart.dart';

import '../../../data/backup/backup_file.dart';
import '../../../data/backup/backup_service.dart';
import '../../../data/backup/drive_client.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../settings/settings_parts.dart';
import 'backup_parts.dart';
import 'passphrase_screen.dart';
import 'restore_screen.dart';

/// Backup (design 06e): daily Drive backup, the copies on Drive (tap to
/// restore), passphrase, and import from a file.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _State {
  const _State(this.account, this.lastAt, this.payments, this.size, this.error);

  final String? account;
  final DateTime? lastAt;
  final int? payments;
  final int? size;
  final String? error;
}

class _BackupScreenState extends State<BackupScreen> {
  final _backup = getIt<BackupService>();
  final _settings = getIt<SettingsRepository>();
  late final Stream<_State> _state = Rx.combineLatest5(
    _settings.watch(BackupService.account),
    _settings.watchDate(BackupService.lastAt),
    _settings.watch(BackupService.lastPayments),
    _settings.watch(BackupService.lastSize),
    _settings.watch(BackupService.error),
    (a, at, p, s, e) => _State(
      a,
      at,
      int.tryParse(p ?? ''),
      int.tryParse(s ?? ''),
      e == null || e.isEmpty ? null : e,
    ),
  );

  Future<List<DriveBackup>>? _drive;
  String? _driveFor;
  bool _allCopies = false;
  bool _busy = false;
  bool? _hasPassphrase;

  @override
  void initState() {
    super.initState();
    _loadPassphrase();
  }

  Future<void> _loadPassphrase() async {
    final has = await _backup.hasPassphrase;
    if (mounted) setState(() => _hasPassphrase = has);
  }

  /// Drive list, refetched when the account or the last backup changes.
  Future<List<DriveBackup>> _copies(_State s) {
    final key = '${s.account}|${s.lastAt}';
    if (_drive == null || _driveFor != key) {
      _driveFor = key;
      _drive = _backup.listDrive();
    }
    return _drive!;
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadPassphrase();
    }
  }

  Future<void> _toggle(bool on, _State s) => _run(() async {
    if (on) {
      await turnOnBackup(context);
    } else {
      await _backup.turnOff();
    }
  });

  Future<void> _openDrive(DriveBackup b) => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await _backup.download(b.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RestoreScreen(file: file, source: 'from Drive'),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't download it. Check the connection."),
        ),
      );
    }
  });

  /// A phone without backup set up (new phone): sign in, then list.
  Future<void> _findOnDrive() => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _backup.listDriveSigningIn();
      setState(() => _drive = null);
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't sign in to Google")),
        );
      }
    }
  });

  Future<void> _import() => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    try {
      final file = BackupFile.parse(await picked.readAsBytes());
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RestoreScreen(file: file, source: 'from a file'),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Can't open ${picked.name}: ${e.message}")),
      );
    }
  });

  Future<void> _changePassphrase() async {
    final has = _hasPassphrase ?? false;
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => PassphraseScreen(
          title: has ? 'New passphrase' : 'Backup passphrase',
          action: has ? 'Use this passphrase' : 'Save passphrase',
        ),
      ),
    );
    await _loadPassphrase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Backup'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: StreamBuilder<_State>(
        stream: _state,
        builder: (context, snap) {
          final s = snap.data;
          if (s == null) return const SizedBox.shrink();
          final on = s.account != null;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SettingsHead('Google Drive'),
              SettingsItem(
                icon: Symbols.cloud_upload,
                title: 'Daily backup',
                subtitle: on
                    ? '${s.account} · keeps the last ${BackupService.keep}'
                    : 'Off',
                onTap: _busy ? null : () => _toggle(!on, s),
                trailing: Switch(
                  value: on,
                  onChanged: _busy ? null : (v) => _toggle(v, s),
                ),
              ),
              if (on && (s.lastAt != null || s.error != null))
                SettingsItem(
                  icon: s.error == null ? Symbols.check_circle : Symbols.error,
                  iconColor: s.error == null ? null : c.alert,
                  title: s.lastAt == null
                      ? 'No backup yet'
                      : 'Last backup ${whenShort(s.lastAt!)}',
                  subtitle:
                      s.error ??
                      [
                        if (s.payments != null)
                          '${grouped(s.payments!)} payments',
                        if (s.size != null) sizeShort(s.size!),
                      ].join(' · '),
                  subtitleColor: s.error == null ? null : c.alert,
                ),
              if (on)
                Padding(
                  padding: const EdgeInsets.fromLTRB(60, 4, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => backUpNow(ScaffoldMessenger.of(context)),
                            ),
                      icon: const Icon(Symbols.backup, size: 18),
                      label: const Text('Back up now'),
                    ),
                  ),
                ),
              const SettingsHead('On Drive'),
              if (!on)
                SettingsItem(
                  icon: Symbols.manage_search,
                  title: 'Find backups on Drive',
                  subtitle: 'Sign in to the account they were saved to',
                  onTap: _busy ? null : _findOnDrive,
                  trailing: const SettingsChevron(),
                )
              else
                FutureBuilder<List<DriveBackup>>(
                  future: _copies(s),
                  builder: (context, list) {
                    if (list.hasError) {
                      return SettingsItem(
                        icon: Symbols.cloud_off,
                        title: "Couldn't list Drive",
                        subtitle: list.error is DriveAuthException
                            ? 'Sign in again: turn backup off and on'
                            : 'Check the connection',
                        onTap: () => setState(() => _drive = null),
                      );
                    }
                    final copies = list.data;
                    if (copies == null) {
                      return const SettingsItem(
                        icon: Symbols.history,
                        title: 'Looking…',
                        subtitle: 'Reading your backups',
                      );
                    }
                    if (copies.isEmpty) {
                      return const SettingsItem(
                        icon: Symbols.history,
                        title: 'None yet',
                        subtitle: 'First one tonight',
                      );
                    }
                    final shown = _allCopies ? copies : copies.take(3).toList();
                    final more = copies.length - shown.length;
                    return Column(
                      children: [
                        for (final b in shown)
                          SettingsItem(
                            icon: Symbols.history,
                            title: _cap(whenShort(b.createdAt)),
                            subtitle: [
                              if (b.payments != null)
                                '${grouped(b.payments!)} payments',
                              sizeShort(b.size),
                            ].join(' · '),
                            onTap: _busy ? null : () => _openDrive(b),
                            trailing: const SettingsChevron(),
                          ),
                        if (more > 0)
                          SettingsItem(
                            icon: Symbols.more_horiz,
                            iconColor: c.text3,
                            title: '$more older',
                            subtitle:
                                'Back to ${dayShort(copies.last.createdAt)}',
                            onTap: () => setState(() => _allCopies = true),
                            trailing: const SettingsChevron(),
                          ),
                      ],
                    );
                  },
                ),
              const SettingsHead('Passphrase'),
              SettingsItem(
                icon: Symbols.key,
                title: _hasPassphrase == false
                    ? 'Set a passphrase'
                    : 'Change passphrase',
                subtitle: _hasPassphrase == false
                    ? 'Locks backups and backup files'
                    : 'Older backups need the old one',
                onTap: _busy ? null : _changePassphrase,
                trailing: const SettingsChevron(),
              ),
              const SettingsHead('From a file'),
              SettingsItem(
                icon: Symbols.upload_file,
                title: 'Import a backup file',
                subtitle: 'A .${BackupFile.extension} file from Export',
                onTap: _busy ? null : _import,
                trailing: const SettingsChevron(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Symbols.lock, size: 16, color: c.text3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Backups are encrypted here with your passphrase. '
                        'Without it nobody can open them, not even k.',
                        style: t.meta.copyWith(color: c.text3, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
}
