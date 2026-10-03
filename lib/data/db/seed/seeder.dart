import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../app_database.dart';
import '../enums.dart';
import 'seed_data.dart';

/// Idempotent (insertOrIgnore + stable ids) — safe to re-run on upgrades.
class Seeder {
  Seeder(this._db);

  final AppDatabase _db;

  Future<void> seedAll() => _db.batch((b) {
    const ignore = InsertMode.insertOrIgnore;

    b.insertAll(_db.banks, [
      for (final bank in builtInBanks)
        BanksCompanion.insert(id: Value(bank.code), name: bank.name),
    ], mode: ignore);

    b.insertAll(_db.senderRules, [
      for (final bank in builtInBanks)
        for (final rule in bank.senderRules)
          SenderRulesCompanion.insert(
            id: Value('sr_${rule.channel.name}_${rule.pattern}'),
            bankId: rule.bankCode,
            channel: rule.channel,
            pattern: rule.pattern,
          ),
    ], mode: ignore);

    b.insertAll(_db.categories, [
      for (final (i, (id, name, icon, color)) in seedCategories.indexed)
        CategoriesCompanion.insert(
          id: Value(id),
          name: name,
          icon: icon,
          color: color,
          isSystem: const Value(true),
          sortOrder: Value(i),
        ),
    ], mode: ignore);

    b.insertAll(_db.categoryRules, [
      for (final e in seedKeywords.entries)
        for (final keyword in e.value)
          CategoryRulesCompanion.insert(
            id: Value('kw_${keyword.replaceAll(' ', '_')}'),
            matchType: RuleMatchType.keyword,
            pattern: keyword,
            categoryId: e.key,
            origin: RuleOrigin.system,
          ),
    ], mode: ignore);

    b.insertAll(_db.appSettings, [
      for (final e in seedSettings.entries)
        AppSettingsCompanion.insert(key: e.key, value: e.value),
    ], mode: ignore);
  });
}
