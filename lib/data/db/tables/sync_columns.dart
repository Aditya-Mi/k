import 'package:drift/drift.dart';

import '../../../core/ids.dart';

/// Columns every syncable table carries. UUID keys + timestamps let a future
/// multi-device sync merge rows without id clashes (last-write-wins on updatedAt).
mixin SyncColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  /// Soft delete: rows are never hard-deleted so deletions can sync too.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
