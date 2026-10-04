import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../../platform/sms_bridge.dart';
import '../db/app_database.dart';
import '../email/google_auth.dart';
import '../repositories/settings_repository.dart';
import 'backup_file.dart';
import 'csv_export.dart';
import 'drive_client.dart';
import 'snapshot.dart';

/// Daily encrypted Drive backup, export and restore (designs 06e–06h).
///
/// The passphrase itself is never stored: k keeps the Argon2id-derived key
/// and its salt in secure storage, so the worker can back up unattended and
/// a backup made with the same salt restores without asking.
class BackupService {
  BackupService(
    this._db,
    this._settings,
    this._secrets,
    this._google,
    this._bridge, {
    this.onRestored,
  });

  final AppDatabase _db;
  final SettingsRepository _settings;
  final FlutterSecureStorage _secrets;
  final GoogleAuth _google;
  final SmsBridge _bridge;

  /// Caches and schedules to rebuild after a restore.
  final Future<void> Function()? onRestored;

  /// Google account backups go to; null = Drive backup off.
  static const account = 'device.backup.account';
  static const lastAt = 'device.backup.lastAt';
  static const lastPayments = 'device.backup.lastPayments';
  static const lastSize = 'device.backup.lastSize';
  static const error = 'device.backup.error';
  static const _folder = 'device.backup.folderId';
  static const _keySecret = 'backup.key';
  static const _kdfSecret = 'backup.kdf';

  static const keep = 7;

  /// Worker runs daily; this stops a second run the same day.
  static const _minGap = Duration(hours: 20);

  Future<bool> get hasPassphrase async =>
      await _secrets.read(key: _keySecret) != null;

  Future<String?> get driveAccount => _settings.get(account);

  /// New salt + key; later backups use it. Older files keep needing the
  /// passphrase they were made with.
  Future<void> setPassphrase(String passphrase) async {
    final kdf = KdfParams.fresh();
    await _storeKey(kdf, await kdf.derive(passphrase));
  }

  /// Account picker + Drive consent, then the daily worker.
  Future<String> connectDrive() async {
    final email = await _google.signIn(scope: GoogleAuth.driveScope);
    await _settings.set(account, email);
    await _settings.set(error, '');
    await _bridge.scheduleBackup(on: true);
    return email;
  }

  /// Stops the worker. Google access stays (Gmail may use the account).
  Future<void> turnOff() async {
    await _db.customStatement(
      "DELETE FROM app_settings WHERE key IN (?, ?, ?)",
      [account, error, _folder],
    );
    await _bridge.scheduleBackup(on: false);
  }

  /// Keeps the worker matching the setting; backs up when the worker has
  /// fallen behind (phone off overnight, battery saver).
  Future<void> refresh() async {
    final on = await driveAccount != null;
    await _bridge.scheduleBackup(on: on);
    if (on) await runIfDue(const Duration(hours: 36));
  }

  Future<bool> runIfDue([Duration gap = _minGap]) async {
    if (await driveAccount == null) return false;
    if (!await hasPassphrase) {
      await _settings.set(error, 'Set a passphrase to start backing up');
      return false;
    }
    final last = DateTime.tryParse(await _settings.get(lastAt) ?? '');
    if (last != null && DateTime.now().difference(last) < gap) return false;
    await backupNow();
    return true;
  }

  /// Seal, upload, keep the newest [keep]. Failures are recorded for
  /// Settings and rethrown.
  Future<void> backupNow() async {
    final email = await driveAccount;
    if (email == null) throw StateError('Drive backup is off');
    try {
      final (bytes, meta) = await _seal();
      final drive = _drive(email);
      final folder = await _folderId(drive);
      await drive.upload(
        folderId: folder,
        name: fileName(meta.createdAt),
        bytes: bytes,
        properties: {'payments': '${meta.payments}'},
      );
      final all = await drive.list(folder);
      for (final old in all.skip(keep)) {
        await drive.delete(old.id);
      }
      await _settings.set(lastAt, meta.createdAt.toIso8601String());
      await _settings.set(lastPayments, '${meta.payments}');
      await _settings.set(lastSize, '${bytes.length}');
      await _settings.set(error, '');
    } catch (e) {
      await _settings.set(
        error,
        e is DriveAuthException
            ? 'Sign in with Google again'
            : 'Last try failed: $e',
      );
      rethrow;
    }
  }

  Future<List<DriveBackup>> listDrive() async {
    final email = await driveAccount;
    if (email == null) return const [];
    final drive = _drive(email);
    return drive.list(await _folderId(drive));
  }

  /// Drive list on a phone where backup isn't set up yet (restoring onto a
  /// new phone): signs in for Drive first.
  Future<List<DriveBackup>> listDriveSigningIn() async {
    if (await driveAccount == null) await connectDrive();
    return listDrive();
  }

  Future<BackupFile> download(String fileId) async {
    final email = await driveAccount;
    if (email == null) throw StateError('Drive backup is off');
    return BackupFile.parse(await _drive(email).download(fileId));
  }

  /// The encrypted backup file for Export (needs a passphrase set).
  Future<(Uint8List, String)> exportFile() async {
    final (bytes, meta) = await _seal();
    return (bytes, fileName(meta.createdAt));
  }

  Future<(Uint8List, String)> exportCsv() async => (
    Uint8List.fromList(utf8.encode(await CsvExport(_db).build())),
    'k-payments-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
  );

  /// True when this phone's saved key opens [file] (same passphrase + salt).
  Future<bool> opensWithSavedKey(BackupFile file) async {
    final kdf = await _savedKdf();
    return kdf != null && kdf.sameAs(file.header.kdf);
  }

  /// Replaces this phone's data with [file]. With a [passphrase] the key is
  /// derived from it, and kept, so backups go on with the same passphrase.
  /// Throws [BackupKeyException] on a wrong passphrase.
  Future<void> restore(BackupFile file, {String? passphrase}) async {
    final Uint8List key;
    if (passphrase != null) {
      key = await file.header.kdf.derive(passphrase);
    } else {
      final saved = await _secrets.read(key: _keySecret);
      if (saved == null || !await opensWithSavedKey(file)) {
        throw const BackupKeyException();
      }
      key = base64Decode(saved);
    }
    final snapshot = await file.open(key);
    await Snapshot(_db).restore(snapshot);
    if (passphrase != null) await _storeKey(file.header.kdf, key);
    await onRestored?.call();
  }

  static String fileName(DateTime at) =>
      'k-${DateFormat('yyyy-MM-dd-HHmm').format(at)}.${BackupFile.extension}';

  Future<(Uint8List, BackupMeta)> _seal() async {
    final saved = await _secrets.read(key: _keySecret);
    final kdf = await _savedKdf();
    if (saved == null || kdf == null) throw StateError('No backup passphrase');
    final (snapshot, meta) = await Snapshot(_db).take();
    final bytes = await BackupFile.seal(
      snapshot: snapshot,
      meta: meta,
      kdf: kdf,
      key: base64Decode(saved),
    );
    return (bytes, meta);
  }

  Future<KdfParams?> _savedKdf() async {
    final raw = await _secrets.read(key: _kdfSecret);
    return raw == null
        ? null
        : KdfParams.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _storeKey(KdfParams kdf, Uint8List key) async {
    await _secrets.write(key: _keySecret, value: base64Encode(key));
    await _secrets.write(key: _kdfSecret, value: jsonEncode(kdf.toJson()));
  }

  DriveClient _drive(String email) => DriveClient(
    accessToken: () => _google.token(email, scope: GoogleAuth.driveScope),
    dropToken: _google.forget,
  );

  Future<String> _folderId(DriveClient drive) async {
    final saved = await _settings.get(_folder);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = await drive.folder();
    await _settings.set(_folder, id);
    return id;
  }
}
