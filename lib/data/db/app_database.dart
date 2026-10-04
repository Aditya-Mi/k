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
  int get schemaVersion => 3;

  /// Alerts that name no account used to create a "no last4" account even when
  /// the bank had exactly one savings/current account; move those rows over.
  Future<void> _foldDigitlessAccounts() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pairs = await customSelect('''
      SELECT n.id AS orphan, (
        SELECT a.id FROM accounts a
        WHERE a.bank_id = n.bank_id AND a.last4 IS NOT NULL
          AND a.deleted_at IS NULL AND a.type IN ('savings', 'current')
      ) AS target
      FROM accounts n
      WHERE n.last4 IS NULL AND n.deleted_at IS NULL
        AND (SELECT count(*) FROM accounts a
             WHERE a.bank_id = n.bank_id AND a.last4 IS NOT NULL
               AND a.deleted_at IS NULL
               AND a.type IN ('savings', 'current')) = 1
    ''').get();
    for (final row in pairs) {
      final orphan = row.read<String>('orphan');
      final target = row.read<String>('target');
      await customStatement(
        'UPDATE transactions SET account_id = ?, updated_at = ? '
        'WHERE account_id = ?',
        [target, now, orphan],
      );
      await customStatement(
        'UPDATE accounts SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, orphan],
      );
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await Seeder(this).seedAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(transactions, transactions.transferId);
        await m.addColumn(transactions, transactions.autoTransferOff);
        await m.create(txnTransfer);
      }
      if (from < 3) {
        await m.addColumn(transactions, transactions.origin);
        await m.addColumn(accounts, accounts.manualBalanceMinor);
        await m.addColumn(accounts, accounts.manualBalanceAt);
        await _foldDigitlessAccounts();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
