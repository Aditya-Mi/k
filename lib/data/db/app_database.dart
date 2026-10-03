import 'package:drift/drift.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../core/ids.dart';
import 'enums.dart';
import 'seed/seeder.dart';
import 'tables/ledger_tables.dart';
import 'tables/reference_tables.dart';
import 'tables/settings_tables.dart';
import 'tables/subscription_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Banks,
    SenderRules,
    Categories,
    Merchants,
    MerchantAliases,
    CategoryRules,
    ParserTemplates,
    Accounts,
    RawMessages,
    Transactions,
    TransactionSources,
    Subscriptions,
    UpcomingCharges,
    EmailAccounts,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await Seeder(this).seedAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
