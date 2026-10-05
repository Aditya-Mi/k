import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart';
import 'package:k/data/db/enums.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/ingest/transfer_linker.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/ui/screens/transactions/transactions_cubit.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:txn_parser/txn_parser.dart';

IncomingMessage sms(String sender, String body, DateTime at) => IncomingMessage(
  channel: Channel.sms,
  sender: sender,
  body: body,
  receivedAt: at,
);

/// Axis UPI debit of [rupees] from XX0640.
IncomingMessage axisOut(
  int rupees,
  DateTime at, {
  String payee = 'RAHUL SHARMA',
}) => sms(
  'AX-AXISBK-S',
  'INR $rupees.00 debited\nA/c no. XX0640\n'
      '${_d(at)}, ${_t(at)}\nUPI/P2A/16617958${at.minute}428/$payee\n'
      'Not you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank',
  at,
);

/// Kotak UPI credit of [rupees] into 4410.
IncomingMessage kotakIn(
  int rupees,
  DateTime at, {
  String from = 'RAHUL SHARMA',
}) => sms(
  'JD-KOTAKB-S',
  'Received Rs.$rupees.00 in your Kotak Bank AC 4410 from $from on '
      '${_d(at)}.UPI Ref:1234567890${at.minute.toString().padLeft(2, '0')}',
  at,
);

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.year % 100}';
String _t(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;
  late TransferLinker linker;
  final oct = TxnFilter.month(DateTime(2026, 10));

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ingest = IngestionService(db);
    ledger = LedgerRepository(db);
    linker = TransferLinker(db);
  });
  tearDown(() => db.close());

  Future<List<TxnView>> txns() => ledger.watchTransactions(oct).first;

  test('debit and matching credit on another account link on ingest', () async {
    await ingest.ingest(axisOut(5000, DateTime(2026, 10, 2, 10, 0)));
    await ingest.ingest(kotakIn(5000, DateTime(2026, 10, 2, 10, 4)));

    final rows = await txns();
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.isTransfer), isTrue);
    expect(rows.first.transferId, rows.last.transferId);
    expect(rows.every((r) => r.category?.id == transfersCategoryId), isTrue);
    final out = rows.firstWhere((r) => r.isDebit);
    expect(out.transferRoute, 'Axis ··0640 → Kotak ··4410');
    final into = rows.firstWhere((r) => !r.isDebit);
    expect(into.transferRoute, 'Axis ··0640 → Kotak ··4410');
    expect(into.transferPartnerId, out.id);

    final summary = summarize(oct.from, rows);
    expect(summary.spentMinor, 0);
    expect(summary.inMinor, 0);
    expect(summary.spends, 0);
  });

  test('outside 30 minutes or different amount does not link', () async {
    await ingest.ingest(axisOut(5000, DateTime(2026, 10, 2, 10, 0)));
    await ingest.ingest(kotakIn(5000, DateTime(2026, 10, 2, 10, 45)));
    await ingest.ingest(axisOut(700, DateTime(2026, 10, 3, 9, 0)));
    await ingest.ingest(kotakIn(750, DateTime(2026, 10, 3, 9, 2)));
    expect((await txns()).where((r) => r.isTransfer), isEmpty);
  });

  test('closest credit in time wins', () async {
    await ingest.ingest(kotakIn(2000, DateTime(2026, 10, 2, 9, 40)));
    await ingest.ingest(kotakIn(2000, DateTime(2026, 10, 2, 10, 2)));
    await ingest.ingest(axisOut(2000, DateTime(2026, 10, 2, 10, 0)));
    final linked = (await txns()).where((r) => r.isTransfer).toList();
    expect(linked, hasLength(2));
    expect(
      linked.firstWhere((r) => !r.isDebit).occurredAt,
      DateTime(2026, 10, 2, 10, 2),
    );
  });

  test('unlink restores categories and is never auto-linked again', () async {
    await ingest.ingest(axisOut(5000, DateTime(2026, 10, 2, 10, 0)));
    await ingest.ingest(kotakIn(5000, DateTime(2026, 10, 2, 10, 4)));
    final out = (await txns()).firstWhere((r) => r.isDebit);

    await linker.unlink(out.id);
    var rows = await txns();
    expect(rows.where((r) => r.isTransfer), isEmpty);
    expect(rows.every((r) => r.category?.id != transfersCategoryId), isTrue);

    expect(await linker.autoLinkAll(), 0);
    rows = await txns();
    expect(rows.where((r) => r.isTransfer), isEmpty);
    expect(summarize(oct.from, rows).spentMinor, 500000);
  });

  test('manual mark with a partner, or one-sided', () async {
    await ingest.ingest(axisOut(5000, DateTime(2026, 10, 2, 10, 0)));
    await ingest.ingest(kotakIn(5000, DateTime(2026, 10, 3, 18, 0)));
    await ingest.ingest(axisOut(900, DateTime(2026, 10, 4, 8, 0)));
    var rows = await txns();
    final out = rows.firstWhere((r) => r.amountMinor == 500000 && r.isDebit);

    final candidates = await linker.candidatesFor(out.id);
    expect(candidates.single.direction, Direction.credit);
    await linker.markManual(out.id, partnerId: candidates.single.id);

    final lone = rows.firstWhere((r) => r.amountMinor == 90000);
    await linker.markManual(lone.id);

    rows = await txns();
    expect(rows.where((r) => r.isTransfer), hasLength(3));
    final loneView = rows.firstWhere((r) => r.id == lone.id);
    expect(loneView.transferPartnerId, isNull);
    expect(loneView.transferRoute, 'Axis ··0640 → own account');
  });

  test('backfill pairs rows logged before linking existed', () async {
    await ingest.ingest(axisOut(5000, DateTime(2026, 10, 2, 10, 0)));
    await ingest.ingest(kotakIn(5000, DateTime(2026, 10, 2, 10, 4)));
    // Simulate pre-2b rows.
    await db
        .update(db.transactions)
        .write(const TransactionsCompanion(transferId: Value(null)));
    expect(await linker.autoLinkAll(), 1);
    expect((await txns()).where((r) => r.isTransfer), hasLength(2));
  });

  test(
    'missing side added on a tracked account, merged when SMS is late',
    () async {
      // BOB account exists from an earlier message.
      await ingest.ingest(
        sms(
          'JD-BOBSMS-S',
          ' Rs.25.00 Dr. from A/C XXXXXX5359 and Cr. to rameshk01@ybl. '
              'Ref:315894910199. AvlBal:Rs18361.03(2026:10:01 10:22:47). '
              'Not you? Call 18005700/5000-BOB',
          DateTime(2026, 10, 1, 10, 23),
        ),
      );
      await ingest.ingest(axisOut(5000, DateTime(2026, 10, 2, 10, 0)));
      final out = (await txns()).firstWhere((r) => r.amountMinor == 500000);
      final bob =
          ((await ledger.watchAccounts().first)
                  .where((a) => !a.isCash)
                  .toList())
              .firstWhere((a) => a.bankId == 'BOB');

      await linker.markManual(out.id, addOnAccountId: bob.id);
      var rows = await txns();
      final added = rows.firstWhere((r) => r.addedByUser);
      expect(added.isDebit, isFalse);
      expect(added.account?.id, bob.id);
      expect(added.transferId, out.transferId == null ? isNotNull : anything);
      expect(
        rows.firstWhere((r) => r.id == out.id).transferRoute,
        'Axis ··0640 → BOB ··5359',
      );
      expect(summarize(oct.from, rows).spentMinor, 2500);

      final detail = await ledger.watchDetail(added.id).first;
      expect(detail!.sourcesFromPartner, isTrue);
      expect(detail.sources.single.sender, 'AX-AXISBK-S');

      // BOB's credit SMS shows up a day late: it becomes the added row.
      await ingest.ingest(
        sms(
          'JD-BOBSMS-S',
          'Dear BOB UPI User: Your account is credited with INR 5000.00 on '
              '2026-10-03 09:00:00 AM by UPI Ref No 292586577667; '
              'AvlBal: Rs23336.03 - BOB',
          DateTime(2026, 10, 3, 9),
        ),
      );
      rows = await txns();
      expect(rows, hasLength(3));
      final merged = rows.firstWhere((r) => r.id == added.id);
      expect(merged.addedByUser, isFalse);
      expect(merged.isTransfer, isTrue);
      expect(merged.balanceMinor, 2333603);
    },
  );

  test('unlinking removes the side the owner added', () async {
    await ingest.ingest(kotakIn(100, DateTime(2026, 9, 30, 9)));
    await ingest.ingest(axisOut(5000, DateTime(2026, 10, 2, 10, 0)));
    final out = (await txns()).firstWhere((r) => r.amountMinor == 500000);
    final kotak =
        ((await ledger.watchAccounts().first).where((a) => !a.isCash).toList())
            .firstWhere((a) => a.bankId == 'KOTAK');
    await linker.markManual(out.id, addOnAccountId: kotak.id);
    expect(await txns(), hasLength(2));
    await linker.unlink(out.id);
    final rows = await txns();
    expect(rows, hasLength(1));
    expect(rows.single.isTransfer, isFalse);
  });

  test('balances: bank figure, estimated after it, manual override', () async {
    // Kotak debit card spend reports Avl bal 18,751.33.
    await ingest.ingest(
      sms(
        'AX-KOTAKB-T',
        'Rs.1504.00 spent via Kotak Debit Card XX4192 at WWW AMAZON IN on '
            '01/10/2026. Avl bal Rs.18751.33 Not you?Tap '
            'https://kotak.bank.in/KBANKT/Fraud',
        DateTime(2026, 10, 1, 19, 45),
      ),
    );
    final acc =
        ((await ledger.watchAccounts().first).where((a) => !a.isCash).toList())
            .single;
    var bal = (await ledger.watchBalances().first)[acc.id]!;
    expect(bal.amountMinor, 1875133);
    expect(bal.estimated, isFalse);
    expect(bal.source, BalanceSource.bank);

    // Two later movements without a balance in the message.
    final t0 = DateTime(2026, 10, 2, 9);
    for (final (amount, dir) in [
      (20000, Direction.debit),
      (5000, Direction.credit),
    ]) {
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: Value(acc.id),
              amountMinor: amount,
              direction: dir,
              txnType: TxnType.upi,
              occurredAt: t0,
            ),
          );
    }
    bal = (await ledger.watchBalances().first)[acc.id]!;
    expect(bal.amountMinor, 1875133 - 20000 + 5000);
    expect(bal.estimatedFrom, 2);

    await ledger.setManualBalance(acc.id, 1000000, DateTime(2026, 10, 3));
    bal = (await ledger.watchBalances().first)[acc.id]!;
    expect(bal.amountMinor, 1000000);
    expect(bal.source, BalanceSource.manual);
    expect(bal.estimated, isFalse);
  });

  test('debit card spend lands on the sole savings account', () async {
    await ingest.ingest(kotakIn(200, DateTime(2026, 9, 28, 11)));
    await ingest.ingest(
      sms(
        'AX-KOTAKB-T',
        'Rs.1504.00 spent via Kotak Debit Card XX4192 at WWW AMAZON IN on '
            '01/10/2026. Avl bal Rs.18751.33 Not you?Tap '
            'https://kotak.bank.in/KBANKT/Fraud',
        DateTime(2026, 10, 1, 19, 45),
      ),
    );
    final accounts = (await ledger.watchAccounts().first)
        .where((a) => !a.isCash)
        .toList();
    expect(accounts, hasLength(1));
    expect(accounts.single.last4, '4410');
    expect(accounts.single.includes, ['card ··4192']);
    final rows = await txns();
    expect(rows.every((r) => r.account?.id == accounts.single.id), isTrue);
    final bal = (await ledger.watchBalances().first)[accounts.single.id]!;
    expect(bal.amountMinor, 1875133);
  });

  test('manual merge moves payments and redirects future messages', () async {
    IncomingMessage axis7777(int rupees, DateTime at) => sms(
      'AX-AXISBK-S',
      'INR $rupees.00 debited\nA/c no. XX7777\n${_d(at)}, ${_t(at)}\n'
          'UPI/P2M/2988338815${at.day}/SWIGGY\n'
          'Not you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank',
      at,
    );
    await ingest.ingest(axisOut(100, DateTime(2026, 10, 1, 9)));
    await ingest.ingest(axis7777(50, DateTime(2026, 10, 1, 10)));
    var accounts = (await ledger.watchAccounts().first)
        .where((a) => !a.isCash)
        .toList();
    final main = accounts.firstWhere((a) => a.last4 == '0640');
    final other = accounts.firstWhere((a) => a.last4 == '7777');
    await ledger.mergeAccount(other.id, main.id);

    accounts = (await ledger.watchAccounts().first)
        .where((a) => !a.isCash)
        .toList();
    expect(accounts.single.id, main.id);
    expect(accounts.single.includes, ['a/c ··7777']);
    await ingest.ingest(axis7777(60, DateTime(2026, 10, 2, 10)));
    final rows = await txns();
    expect(rows, hasLength(3));
    expect(rows.every((r) => r.account?.id == main.id), isTrue);
  });

  test('schema v1 → v4: transfer, origin, balance, merge', () async {
    final dir = Directory.systemTemp.createTempSync('k_mig');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/k.db');

    final v2 = AppDatabase(NativeDatabase(file));
    await v2.banks.count().getSingle();
    // A nameless BOB account from a digitless alert, next to the real one.
    for (final (id, bank, type, last4) in [
      ('real', 'BOB', AccountType.savings, '5359'),
      ('orphan', 'BOB', AccountType.savings, null),
      ('ksav', 'KOTAK', AccountType.savings, '5543'),
      ('kcard', 'KOTAK', AccountType.debitCard, '4192'),
    ]) {
      await v2
          .into(v2.accounts)
          .insert(
            AccountsCompanion.insert(
              id: Value(id),
              bankId: bank,
              type: type,
              last4: Value(last4),
            ),
          );
    }
    await v2
        .into(v2.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: const Value('t2'),
            accountId: const Value('kcard'),
            amountMinor: 150400,
            direction: Direction.debit,
            txnType: TxnType.card,
            occurredAt: DateTime(2026, 10, 1),
          ),
        );
    await v2
        .into(v2.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: const Value('t1'),
            accountId: const Value('orphan'),
            amountMinor: 100,
            direction: Direction.credit,
            txnType: TxnType.upi,
            occurredAt: DateTime(2026, 10, 1),
          ),
        );
    await v2.close();

    // Roll the file back to the v1 shape.
    final r = raw.sqlite3.open(file.path);
    r
      ..execute('DROP INDEX txn_transfer')
      ..execute('ALTER TABLE transactions DROP COLUMN transfer_id')
      ..execute('ALTER TABLE transactions DROP COLUMN auto_transfer_off')
      ..execute('ALTER TABLE transactions DROP COLUMN origin')
      ..execute('ALTER TABLE accounts DROP COLUMN manual_balance_minor')
      ..execute('ALTER TABLE accounts DROP COLUMN manual_balance_at')
      ..execute('ALTER TABLE accounts DROP COLUMN merged_into_id')
      ..execute('ALTER TABLE merchants DROP COLUMN merged_into_id')
      ..execute('ALTER TABLE categories DROP COLUMN hidden')
      ..execute('PRAGMA user_version = 1')
      ..close();

    final upgraded = AppDatabase(NativeDatabase(file));
    final cols = await upgraded
        .customSelect("SELECT name FROM pragma_table_info('transactions')")
        .map((row) => row.read<String>('name'))
        .get();
    expect(cols, containsAll(['transfer_id', 'auto_transfer_off', 'origin']));
    final accCols = await upgraded
        .customSelect("SELECT name FROM pragma_table_info('accounts')")
        .map((row) => row.read<String>('name'))
        .get();
    expect(accCols, contains('manual_balance_minor'));
    final t1 = await (upgraded.select(
      upgraded.transactions,
    )..where((t) => t.id.equals('t1'))).getSingle();
    expect(t1.accountId, 'real');
    final orphan = await (upgraded.select(
      upgraded.accounts,
    )..where((a) => a.id.equals('orphan'))).getSingle();
    expect(orphan.deletedAt, isNotNull);
    final t2 = await (upgraded.select(
      upgraded.transactions,
    )..where((t) => t.id.equals('t2'))).getSingle();
    expect(t2.accountId, 'ksav');
    final card = await (upgraded.select(
      upgraded.accounts,
    )..where((a) => a.id.equals('kcard'))).getSingle();
    expect(card.mergedIntoId, 'ksav');
    await upgraded.close();
  });
}
