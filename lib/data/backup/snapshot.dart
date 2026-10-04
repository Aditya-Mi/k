import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'backup_file.dart';

/// Whole-database copy for backups: every table's raw rows, plus what the
/// restore screen shows. Device-local settings (`device.*`: SMS cursors,
/// theme, app lock, backup state) are neither saved nor overwritten.
class Snapshot {
  Snapshot(this._db);

  final AppDatabase _db;

  static const _localPrefix = 'device.';

  Future<(Map<String, dynamic>, BackupMeta)> take() =>
      _db.transaction(() async {
        final tables = <String, List<Map<String, dynamic>>>{};
        for (final t in _db.allTables) {
          final rows = await _db
              .customSelect('SELECT * FROM "${t.actualTableName}"')
              .get();
          tables[t.actualTableName] = [
            for (final r in rows)
              if (!_isLocalSetting(t, r.data))
                {for (final e in r.data.entries) e.key: _out(e.value)},
          ];
        }
        final meta = BackupMeta(
          createdAt: DateTime.now(),
          schemaVersion: _db.schemaVersion,
          payments: await _count('transactions'),
          accounts: await _count('accounts', 'AND merged_into_id IS NULL'),
          subscriptions: await _count('subscriptions'),
          formats: await _count('parser_templates'),
        );
        return ({'schema': _db.schemaVersion, 'tables': tables}, meta);
      });

  /// Replaces everything (but device-local settings) with [snapshot].
  /// Columns this version doesn't know are dropped; ones the backup lacks
  /// take their defaults — so older backups still restore.
  Future<void> restore(Map<String, dynamic> snapshot) async {
    final schema = snapshot['schema'] as int;
    if (schema > _db.schemaVersion) {
      throw const FormatException('made by a newer k; update k first');
    }
    final tables = (snapshot['tables'] as Map<String, dynamic>);
    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final t in _db.allTables.toList().reversed) {
        final name = t.actualTableName;
        await _db.customStatement(
          t is $AppSettingsTable
              ? 'DELETE FROM "$name" WHERE key NOT LIKE \'$_localPrefix%\''
              : 'DELETE FROM "$name"',
        );
      }
      for (final t in _db.allTables) {
        final name = t.actualTableName;
        final known = {for (final c in t.$columns) c.name};
        for (final raw in (tables[name] as List<dynamic>? ?? const [])) {
          final row = raw as Map<String, dynamic>;
          if (_isLocalSetting(t, row)) continue;
          final cols = [
            for (final k in row.keys)
              if (known.contains(k)) k,
          ];
          if (cols.isEmpty) continue;
          await _db.customInsert(
            'INSERT OR REPLACE INTO "$name" (${cols.map((c) => '"$c"').join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            variables: [for (final c in cols) Variable(_in(row[c]))],
          );
        }
      }
    });
    // Raw statements bypass drift's change tracking: wake every stream.
    _db.notifyUpdates({for (final t in _db.allTables) TableUpdate.onTable(t)});
  }

  Future<int> _count(String table, [String extra = '']) async {
    final r = await _db
        .customSelect(
          'SELECT count(*) AS n FROM "$table" WHERE deleted_at IS NULL $extra',
        )
        .getSingle();
    return r.read<int>('n');
  }

  static bool _isLocalSetting(TableInfo t, Map<String, dynamic> row) =>
      t is $AppSettingsTable && (row['key'] as String).startsWith(_localPrefix);

  static Object? _out(Object? v) =>
      v is Uint8List ? {r'$b': base64Encode(v)} : v;

  static Object? _in(Object? v) =>
      v is Map ? base64Decode(v[r'$b'] as String) : v;
}
