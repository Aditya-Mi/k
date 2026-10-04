import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Typed access to the key-value `app_settings` table.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  // Device-local keys (SMS cursors differ per phone — exclude from any sync).
  static const smsInboxCursor = 'device.sms.inboxCursor';
  static const smsLastSyncAt = 'device.sms.lastSyncAt';
  static const onboardingDone = 'device.onboarding.done';

  /// `system` (default), `light` or `dark`.
  static const themeMode = 'device.theme';

  Future<String?> get(String key) async => (await (_db.select(
    _db.appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watch(String key) => (_db.select(
    _db.appSettings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((s) => s?.value);

  Future<void> set(String key, String value) => _db
      .into(_db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: key,
          value: value,
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  Future<bool> getBool(String key) async => await get(key) == 'true';

  Stream<DateTime?> watchDate(String key) =>
      watch(key).map((v) => v == null ? null : DateTime.tryParse(v));
}
