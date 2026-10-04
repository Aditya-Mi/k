import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/backup/backup_file.dart';
import 'package:k/data/backup/csv_export.dart';
import 'package:k/data/backup/snapshot.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/db/enums.dart';
import 'package:k/data/repositories/settings_repository.dart';
import 'package:txn_parser/txn_parser.dart';

AppDatabase _memory() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

void main() {
  late AppDatabase a;
  late AppDatabase b;

  setUp(() async {
    a = _memory();
    b = _memory();
    final account = await a
        .into(a.accounts)
        .insertReturning(
          AccountsCompanion.insert(
            bankId: 'AXIS',
            type: AccountType.savings,
            last4: const Value('0640'),
          ),
        );
    await a
        .into(a.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: Value(account.id),
            amountMinor: 25000,
            direction: Direction.debit,
            txnType: TxnType.upi,
            payeeRaw: const Value('Zepto'),
            occurredAt: DateTime(2026, 10, 5, 9, 30),
            notes: const Value('milk'),
          ),
        );
    await SettingsRepository(a).set(SettingsRepository.themeMode, 'dark');
    await SettingsRepository(a).set('dedup.windowMinutes', '30');
    await SettingsRepository(b).set(SettingsRepository.themeMode, 'light');
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  test(
    'snapshot restores into another database, keeping its device settings',
    () async {
      final (snap, meta) = await Snapshot(a).take();
      expect(meta.payments, 1);
      expect(meta.accounts, 2); // + the seeded Cash account

      await Snapshot(b).restore(snap);

      final txns = await b.select(b.transactions).get();
      expect(txns.single.amountMinor, 25000);
      expect(txns.single.notes, 'milk');
      expect(txns.single.occurredAt, DateTime(2026, 10, 5, 9, 30));
      final settings = SettingsRepository(b);
      expect(await settings.get('dedup.windowMinutes'), '30');
      // device.* stays the phone's own.
      expect(await settings.get(SettingsRepository.themeMode), 'light');
      // Seeded rows came across once, not twice.
      expect(
        (await b.select(b.banks).get()).length,
        (await a.select(a.banks).get()).length,
      );
    },
  );

  test(
    'sealed file opens with the right key only, and its header is bound',
    () async {
      final (snap, meta) = await Snapshot(a).take();
      final kdf = KdfParams(
        salt: List.filled(16, 7),
        memoryKib: 64,
        iterations: 1,
      );
      final key = await kdf.derive('correct horse battery staple');
      final bytes = await BackupFile.seal(
        snapshot: snap,
        meta: meta,
        kdf: kdf,
        key: key,
      );

      final file = BackupFile.parse(bytes);
      expect(file.header.meta.payments, 1);
      expect(file.header.kdf.sameAs(kdf), isTrue);
      expect((await file.open(key))['tables'], isNotEmpty);

      final wrong = await kdf.derive('wrong');
      expect(() => file.open(wrong), throwsA(isA<BackupKeyException>()));

      final tampered = String.fromCharCodes(bytes)
          .replaceFirst(r'\"payments\":1', r'\"payments\":9');
      expect(
        () => BackupFile.parse(tampered.codeUnits).open(key),
        throwsA(isA<BackupKeyException>()),
      );
    },
  );

  test('not a backup → FormatException', () {
    expect(() => BackupFile.parse('hello'.codeUnits), throwsFormatException);
  });

  test('CSV lists payments with signed rupees and guarded cells', () async {
    await a
        .into(a.transactions)
        .insert(
          TransactionsCompanion.insert(
            amountMinor: 120005,
            direction: Direction.credit,
            txnType: TxnType.neft,
            payeeRaw: const Value('=HYPERLINK("x"), Inc'),
            occurredAt: DateTime(2026, 10, 6, 18, 5),
          ),
        );
    final lines = (await CsvExport(a).build()).split('\r\n');
    expect(lines.first, CsvExport.columns.join(','));
    expect(lines[1], startsWith('2026-10-05,09:30,-250.00,INR,paid,Zepto,'));
    expect(lines[1], contains(',milk,'));
    expect(
      lines[2],
      '2026-10-06,18:05,1200.05,INR,received,"\'=HYPERLINK(""x""), Inc",,,neft,,,',
    );
  });
}
