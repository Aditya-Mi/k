import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../enums.dart';
import 'sync_columns.dart';

/// id = bank code ('AXIS', 'KOTAK', 'BOB') so seeds are stable across devices.
class Banks extends Table with SyncColumns {
  TextColumn get name => text()();
}

class SenderRules extends Table with SyncColumns {
  TextColumn get bankId => text().references(Banks, #id)();
  TextColumn get channel => textEnum<Channel>()();

  /// SMS: header core, case-insensitive substring ("AXISBK" ⊂ "AX-AXISBK-S").
  /// Email: address or domain suffix ("axisbank.com").
  TextColumn get pattern => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {channel, pattern},
  ];
}

class Categories extends Table with SyncColumns {
  TextColumn get name => text()();

  /// Material icon name, resolved in UI.
  TextColumn get icon => text()();

  /// ARGB.
  IntColumn get color => integer()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class Merchants extends Table with SyncColumns {
  TextColumn get normalizedKey => text().unique()();
  TextColumn get displayName => text()();

  /// Folded into another merchant (owner gave both the same name). Kept so
  /// its key still resolves; ingestion follows this to the target.
  TextColumn get mergedIntoId => text().nullable()();
}

/// Many raw payee strings ("swiggy.upi@axb", "SWIGGY BANGALORE") → one merchant.
class MerchantAliases extends Table with SyncColumns {
  TextColumn get alias => text().unique()();
  TextColumn get merchantId => text().references(Merchants, #id)();
}

class CategoryRules extends Table with SyncColumns {
  TextColumn get matchType => textEnum<RuleMatchType>()();

  /// merchant → Merchants.normalizedKey; keyword → lowercase word(s),
  /// matched on word boundaries, longest keyword wins ("jiomart" beats "jio").
  TextColumn get pattern => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get origin => textEnum<RuleOrigin>()();
}

/// User-created templates only; built-ins live in txn_parser code.
class ParserTemplates extends Table with SyncColumns {
  TextColumn get bankId => text().references(Banks, #id)();
  TextColumn get channel => textEnum<Channel>()();
  TextColumn get kind => textEnum<TemplateKind>()();
  TextColumn get name => text()();

  /// Regex with named groups: amount, last4, merchant, ref, date, balance...
  TextColumn get pattern => text()();

  /// JSON: fixed field values when not captured, e.g. {"direction":"debit"}.
  TextColumn get fieldDefaults => text().withDefault(const Constant('{}'))();

  /// JSON array of intl date patterns tried in order.
  TextColumn get dateFormats => text().withDefault(const Constant('[]'))();
  IntColumn get priority => integer().withDefault(const Constant(100))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get sampleRawMessageId => text().nullable()();
}
