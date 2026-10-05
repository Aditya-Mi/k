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
  int get schemaVersion => 8;

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

  /// Folds [sourceId] into [targetId]: payments, aliases, subscriptions and
  /// upcoming charges move over; its "use for all" category rule moves too
  /// unless the target has its own. The source row stays as a pointer.
  Future<void> mergeMerchant(String sourceId, String targetId) async {
    if (sourceId == targetId) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final table in const [
      'transactions',
      'subscriptions',
      'upcoming_charges',
      'merchant_aliases',
    ]) {
      await customStatement(
        'UPDATE $table SET merchant_id = ?, updated_at = ? '
        'WHERE merchant_id = ?',
        [targetId, now, sourceId],
      );
    }
    final keys = await customSelect(
      'SELECT id, normalized_key FROM merchants WHERE id IN (?, ?)',
      variables: [Variable(sourceId), Variable(targetId)],
    ).get();
    String keyOf(String id) => keys
        .firstWhere((r) => r.read<String>('id') == id)
        .read<String>('normalized_key');
    final sKey = keyOf(sourceId), tKey = keyOf(targetId);
    final targetRule = await customSelect(
      "SELECT 1 FROM category_rules WHERE match_type = 'merchant' "
      'AND pattern = ? AND deleted_at IS NULL',
      variables: [Variable(tKey)],
    ).get();
    if (targetRule.isEmpty) {
      await customStatement(
        'INSERT OR IGNORE INTO category_rules (id, match_type, pattern, '
        'category_id, priority, origin, created_at, updated_at) '
        "SELECT 'mr_' || ?, match_type, ?, category_id, priority, origin, ?, ? "
        "FROM category_rules WHERE match_type = 'merchant' AND pattern = ? "
        'AND deleted_at IS NULL LIMIT 1',
        [tKey, tKey, now, now, sKey],
      );
    }
    await customStatement(
      'UPDATE category_rules SET deleted_at = ?, updated_at = ? '
      "WHERE match_type = 'merchant' AND pattern = ? AND deleted_at IS NULL",
      [now, now, sKey],
    );
    await customStatement(
      'UPDATE merchants SET merged_into_id = ?, updated_at = ? '
      'WHERE id = ? OR merged_into_id = ?',
      [targetId, now, sourceId, sourceId],
    );
  }

  /// v7: merchants the owner already renamed to the same name become one;
  /// the one with the most payments keeps its row.
  Future<void> mergeSameNameMerchants() async {
    final rows = await customSelect('''
      SELECT m.id, lower(trim(m.display_name)) AS name,
             (SELECT count(*) FROM transactions t WHERE t.merchant_id = m.id)
               AS n
      FROM merchants m
      WHERE m.deleted_at IS NULL AND m.merged_into_id IS NULL
      ORDER BY name, n DESC, m.created_at
    ''').get();
    final keep = <String, String>{};
    for (final r in rows) {
      final name = r.read<String>('name');
      final id = r.read<String>('id');
      final target = keep[name];
      if (target == null) {
        keep[name] = id;
      } else {
        await mergeMerchant(id, target);
      }
    }
  }

  /// A debit card spends from its savings account: fold auto-created debit
  /// card accounts into the bank's only savings/current account.
  /// v5: "Cash" becomes "ATM withdrawal" (unless the owner renamed it), and
  /// ATM-type payments the owner hasn't filed move into it.
  Future<void> _atmCategory() async {
    await customStatement(
      "UPDATE categories SET name = 'ATM withdrawal' "
      "WHERE id = 'cat_cash' AND name = 'Cash'",
    );
    await customStatement(
      "UPDATE transactions SET category_id = 'cat_cash' "
      "WHERE txn_type = 'atm' AND user_edited = 0 AND transfer_id IS NULL",
    );
  }

  Future<void> _foldDebitCards() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pairs = await customSelect('''
      SELECT c.id AS card, (
        SELECT a.id FROM accounts a
        WHERE a.bank_id = c.bank_id AND a.deleted_at IS NULL
          AND a.merged_into_id IS NULL AND a.type IN ('savings', 'current')
      ) AS target
      FROM accounts c
      WHERE c.type = 'debitCard' AND c.deleted_at IS NULL
        AND c.merged_into_id IS NULL
        AND (SELECT count(*) FROM accounts a
             WHERE a.bank_id = c.bank_id AND a.deleted_at IS NULL
               AND a.merged_into_id IS NULL
               AND a.type IN ('savings', 'current')) = 1
    ''').get();
    for (final row in pairs) {
      final card = row.read<String>('card');
      final target = row.read<String>('target');
      await customStatement(
        'UPDATE transactions SET account_id = ?, updated_at = ? '
        'WHERE account_id = ?',
        [target, now, card],
      );
      await customStatement(
        'UPDATE accounts SET merged_into_id = ?, updated_at = ? WHERE id = ?',
        [target, now, card],
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
      if (from < 4) {
        await m.addColumn(accounts, accounts.mergedIntoId);
        await _foldDebitCards();
      }
      if (from < 5) await _atmCategory();
      // v6: the Cash account (seeded; seedAll is idempotent).
      if (from < 6) await Seeder(this).seedAll();
      if (from < 7) {
        await m.addColumn(merchants, merchants.mergedIntoId);
        await mergeSameNameMerchants();
      }
      if (from < 8) await m.addColumn(categories, categories.hidden);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
