import 'package:drift/drift.dart';

import '../enums.dart';
import 'sync_columns.dart';

class EmailAccounts extends Table with SyncColumns {
  TextColumn get email => text()();
  TextColumn get authType => textEnum<EmailAuthType>()();

  /// Gmail historyId or IMAP UID. Device-local — excluded from future sync.
  TextColumn get syncCursor => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {email, authType},
  ];
}

/// Key-value settings (dedup window, tolerance, reminder days, cursors).
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
