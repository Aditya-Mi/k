// Every schema the app has shipped upgrades to the current one, matches it
// exactly, and keeps the owner's data. Old schemas live in drift_schemas/
// (one JSON per version) and test/generated_migrations/.
//
// After a schema change: bump schemaVersion, then
//   dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/drift_schema_vN.json
//   dart run drift_dev schema generate --data-classes --companions drift_schemas/ test/generated_migrations/
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart';

import '../generated_migrations/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  const current = 9;

  /// Rows an owner would have: a bank, an account, a payee, a payment.
  /// Columns used exist (and are required) in every version.
  Future<void> fill(GeneratedDatabase e) async {
    const t = 1759600000; // 2025-10-04, unix seconds
    await e.customStatement(
      'INSERT INTO banks (id, created_at, updated_at, name) '
      "VALUES ('ZZBANK', $t, $t, 'Test Bank')",
    );
    await e.customStatement(
      'INSERT INTO accounts (id, created_at, updated_at, bank_id, type, last4) '
      "VALUES ('acc_1', $t, $t, 'ZZBANK', 'savings', '1111')",
    );
    await e.customStatement(
      'INSERT INTO merchants (id, created_at, updated_at, normalized_key, '
      "display_name) VALUES ('m_1', $t, $t, 'zepto', 'Zepto')",
    );
    await e.customStatement(
      'INSERT INTO transactions (id, created_at, updated_at, account_id, '
      'merchant_id, amount_minor, direction, txn_type, occurred_at) '
      "VALUES ('t_1', $t, $t, 'acc_1', 'm_1', 41200, 'debit', 'upi', $t)",
    );
  }

  for (var from = 1; from < current; from++) {
    test('v$from → v$current keeps data and matches the schema', () async {
      final schema = await verifier.schemaAt(from);
      final old = GeneratedHelper().databaseForVersion(
        schema.newConnection(),
        from,
      );
      await fill(old);
      await old.close();

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, current);

      final txn = await (db.select(
        db.transactions,
      )..where((x) => x.id.equals('t_1'))).getSingle();
      expect(txn.amountMinor, 41200);
      expect(txn.accountId, 'acc_1');
      expect(txn.merchantId, 'm_1');
      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals('acc_1'))).getSingle();
      expect(account.last4, '1111');
      expect(account.mergedIntoId, isNull);
      // Seeds reach upgraded installs (the Cash account, v6).
      expect(
        await (db.select(
          db.accounts,
        )..where((a) => a.id.equals('acc_cash'))).getSingleOrNull(),
        isNotNull,
      );
      await db.close();
    });
  }
}
