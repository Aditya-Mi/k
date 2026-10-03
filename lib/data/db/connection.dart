import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

const _dbFileName = 'k.db';

/// Opens the SQLite3MultipleCiphers-encrypted database with [key].
QueryExecutor openEncryptedDatabase(String key) {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _dbFileName));
    // Android has no /tmp; point sqlite at the app cache dir.
    sqlite3.tempDirectory = (await getTemporaryDirectory()).path;

    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) => applyKey(rawDb, key),
    );
  });
}

/// Refuses to continue on a non-cipher sqlite build — never write plaintext.
void applyKey(Database rawDb, String key) {
  if (rawDb.select('PRAGMA cipher;').isEmpty) {
    throw StateError('sqlite3mc not bundled: refusing to open unencrypted DB');
  }
  rawDb.execute("PRAGMA key = '$key';");
  // Fails fast with "file is not a database" if the key is wrong.
  rawDb.select('SELECT count(*) FROM sqlite_master;');
}
