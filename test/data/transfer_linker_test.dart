import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart';
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

  test('schema v1 → v2 adds the transfer columns', () async {
    final dir = Directory.systemTemp.createTempSync('k_mig');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/k.db');

    final v2 = AppDatabase(NativeDatabase(file));
    await v2.banks.count().getSingle();
    await v2.close();

    // Roll the file back to the v1 shape.
    final r = raw.sqlite3.open(file.path);
    r
      ..execute('DROP INDEX txn_transfer')
      ..execute('ALTER TABLE transactions DROP COLUMN transfer_id')
      ..execute('ALTER TABLE transactions DROP COLUMN auto_transfer_off')
      ..execute('PRAGMA user_version = 1')
      ..close();

    final upgraded = AppDatabase(NativeDatabase(file));
    final cols = await upgraded
        .customSelect("SELECT name FROM pragma_table_info('transactions')")
        .map((row) => row.read<String>('name'))
        .get();
    expect(cols, containsAll(['transfer_id', 'auto_transfer_off']));
    await upgraded.close();
  });
}
