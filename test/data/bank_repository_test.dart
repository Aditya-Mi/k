import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/repositories/bank_repository.dart';
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
}
