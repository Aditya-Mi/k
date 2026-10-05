import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/db/enums.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/bank_repository.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:txn_parser/txn_parser.dart' show Channel;

void main() {
  late AppDatabase db;
  setUp(
    () => db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    ),
  );
  tearDown(() => db.close());

  test(
    'banks list their senders; an added sender shows and refreshes parser',
    () async {
      var changed = 0;
      final repo = BankRepository(db, onRulesChanged: () => changed++);
      final before = await repo.watchBanks().first;
      final axis = before.firstWhere((b) => b.id == 'AXIS');
      expect(axis.sms, isNotEmpty);
      expect(axis.email, contains('axis.bank.in'));

      await repo.addSender('AXIS', Channel.sms, ' axisbn ');
      await repo.addSender('AXIS', Channel.email, 'Alerts@AxisBank.in');
      final after = (await repo.watchBanks().first).firstWhere(
        (b) => b.id == 'AXIS',
      );
      expect(after.sms, contains('AXISBN'));
      expect(after.email, contains('alerts@axisbank.in'));
      expect(changed, 2);

      // Adding the same sender again doesn't duplicate it.
      await repo.addSender('AXIS', Channel.sms, 'AXISBN');
      final again = (await repo.watchBanks().first).firstWhere(
        (b) => b.id == 'AXIS',
      );
      expect(again.sms.where((s) => s == 'AXISBN'), hasLength(1));
    },
  );

  test('an added account is "your bank" and catches its messages', () async {
    final repo = BankRepository(db);
    final ledger = LedgerRepository(db);
    var axis = (await repo.watchBanks().first).firstWhere(
      (b) => b.id == 'AXIS',
    );
    expect(axis.inUse, isFalse);

    final id = await ledger.addAccount(
      bankId: 'AXIS',
      type: AccountType.savings,
      last4: '1234',
      nickname: 'Salary',
      balanceMinor: -250000,
    );
    expect(id, isNotNull);
    expect(
      await ledger.addAccount(
        bankId: 'AXIS',
        type: AccountType.savings,
        last4: '1234',
      ),
      isNull,
      reason: 'same bank and digits twice',
    );
    axis = (await repo.watchBanks().first).firstWhere((b) => b.id == 'AXIS');
    expect(axis.inUse, isTrue);
    expect(axis.accounts, 1);

    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(id!))).getSingle();
    expect(account.manualBalanceMinor, -250000);
    expect(account.autoCreated, isFalse);

    await IngestionService(db).ingest(
      IncomingMessage(
        channel: Channel.sms,
        sender: 'AX-AXISBK-S',
        body:
            'INR 250.00 debited\nA/c no. XX1234\n04-10-26, 10:00:00\n'
            'UPI/P2M/123456789012/ZEPTO\nNot you? SMS BLOCKUPI Cust ID to '
            '919951860002\nAxis Bank',
        receivedAt: DateTime(2026, 10, 4, 10),
      ),
    );
    final txn = await db.select(db.transactions).getSingle();
    expect(txn.accountId, id);
    expect(
      await (db.select(
        db.accounts,
      )..where((a) => a.bankId.equals('AXIS'))).get(),
      hasLength(1),
      reason: 'no second account auto-created for ··1234',
    );
  });

  test(
    'a named bank lands on the catalogue one, else gets a code id',
    () async {
      final repo = BankRepository(db);
      expect(await repo.addBank('HDFC Bank'), 'HDFC');
      expect(await repo.addBank('hdfc'), 'HDFC');
      expect(await repo.addBank('State Bank of India'), 'SBI');
      expect(await repo.addBank('sbi'), 'SBI');
      expect(await repo.addBank('ZZ Bank'), 'ZZ');
      expect(await repo.addBank('zz'), 'ZZ');
      final banks = await repo.watchBanks().first;
      expect(banks.firstWhere((b) => b.id == 'PHONEPE').wallet, isTrue);
      expect(banks.firstWhere((b) => b.id == 'SBI').wallet, isFalse);
    },
  );
}
