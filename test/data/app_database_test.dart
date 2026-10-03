import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart';
import 'package:k/data/db/connection.dart';
import 'package:k/data/db/enums.dart';
import 'package:k/data/db/seed/seed_data.dart';
import 'package:k/data/db/seed/seeder.dart';
import 'package:txn_parser/txn_parser.dart';

void main() {
  group('schema + seeds', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
    });
    tearDown(() => db.close());

    test('seeds banks, senders, categories, keyword rules, settings', () async {
      expect(await db.banks.count().getSingle(), builtInBanks.length);
      expect(
        await db.categories.count().getSingle(),
        seedCategories.length,
      );
      final keywordCount = seedKeywords.values.fold(0, (n, l) => n + l.length);
      expect(await db.categoryRules.count().getSingle(), keywordCount);
      final senders = await db.select(db.senderRules).get();
      expect(senders.map((s) => s.pattern), contains('AXISBK'));
      final window = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('dedup.windowMinutes'))).getSingle();
      expect(window.value, '10');
    });

    test('seeder is idempotent', () async {
      await Seeder(db).seedAll();
      expect(await db.banks.count().getSingle(), builtInBanks.length);
    });

    test('rows get UUIDv7 ids and sync timestamps', () async {
      final account = await db
          .into(db.accounts)
          .insertReturning(
            AccountsCompanion.insert(
              bankId: 'AXIS',
              type: AccountType.savings,
              last4: const Value('1234'),
            ),
          );
      expect(account.id, hasLength(36));
      expect(account.updatedAt, isNotNull);
      expect(account.deletedAt, isNull);
    });

    test('transaction links to many raw messages (dedup)', () async {
      final txn = await db
          .into(db.transactions)
          .insertReturning(
            TransactionsCompanion.insert(
              amountMinor: 25000,
              direction: Direction.debit,
              txnType: TxnType.upi,
              occurredAt: DateTime(2026, 10, 5, 14, 32),
            ),
          );
      for (final (i, ch) in [Channel.sms, Channel.email].indexed) {
        final raw = await db
            .into(db.rawMessages)
            .insertReturning(
              RawMessagesCompanion.insert(
                channel: ch,
                sender: 'AXIS',
                body: 'body $i',
                receivedAt: DateTime(2026, 10, 5),
                contentHash: 'hash$i',
                status: RawMessageStatus.parsed,
              ),
            );
        await db
            .into(db.transactionSources)
            .insert(
              TransactionSourcesCompanion.insert(
                transactionId: txn.id,
                rawMessageId: raw.id,
              ),
            );
      }
      expect(await db.transactionSources.count().getSingle(), 2);
    });

    test('duplicate content hash is rejected', () async {
      RawMessagesCompanion raw() => RawMessagesCompanion.insert(
        channel: Channel.sms,
        sender: 'AX-AXISBK',
        body: 'x',
        receivedAt: DateTime(2026),
        contentHash: 'same',
        status: RawMessageStatus.pending,
      );
      await db.into(db.rawMessages).insert(raw());
      expect(
        () => db.into(db.rawMessages).insert(raw()),
        throwsA(isA<SqliteException>()),
      );
    });

    test('foreign keys are enforced', () async {
      expect(
        () => db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                bankId: 'NOPE',
                type: AccountType.savings,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('encryption', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('k_db_test');
      file = File('${dir.path}/k.db');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    AppDatabase open(String key) => AppDatabase(
      NativeDatabase(file, setup: (raw) => applyKey(raw, key)),
    );

    test('file on disk is not plaintext SQLite', () async {
      final db = open('test-key-123');
      await db.banks.count().getSingle();
      await db.close();

      final header = file.readAsBytesSync().sublist(0, 16);
      expect(String.fromCharCodes(header), isNot(startsWith('SQLite format 3')));
    });

    test('reopens with the right key, fails with a wrong one', () async {
      final db = open('right-key');
      await db.banks.count().getSingle();
      await db.close();

      final again = open('right-key');
      expect(await again.banks.count().getSingle(), builtInBanks.length);
      await again.close();

      final wrong = open('wrong-key');
      await expectLater(wrong.banks.count().getSingle(), throwsA(anything));
      await wrong.close().catchError((_) {});
    });
  });
}
