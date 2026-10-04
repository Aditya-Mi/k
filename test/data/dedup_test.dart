import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:txn_parser/txn_parser.dart';

/// Axis UPI debit SMS and its alert email (real formats, masked).
IncomingMessage sms(int rupees, DateTime at, {String ref = '441151550312'}) =>
    IncomingMessage(
      channel: Channel.sms,
      sender: 'AX-AXISBK-S',
      body:
          'INR $rupees.00 debited\nA/c no. XX0640\n'
          '${_d(at)}, ${_t(at)}\nUPI/P2M/$ref/RAMESH KUMAR\n'
          'Not you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank',
      receivedAt: at,
    );

IncomingMessage email(int rupees, DateTime at, {String ref = '441151550312'}) =>
    IncomingMessage(
      channel: Channel.email,
      sender: 'Axis Bank <alerts@axis.bank.in>',
      subject: 'INR $rupees.00 was debited from your A/c no. XX0640',
      body:
          '${_d(at)}\nDear Customer,\n\nHere\'s the summary of your '
          'transaction:\n\n\nAccount Number:\nXX0640\n\nDate & Time:\n'
          '${_d(at)}, ${_t(at)} IST\n\nTransaction Info:\n'
          'UPI/P2M/$ref/RAMESH KUMAR\n\nRegards,\nAxis Bank Ltd.\n',
      receivedAt: at.add(const Duration(minutes: 1)),
    );

String _two(int n) => n.toString().padLeft(2, '0');
String _d(DateTime d) =>
    '${_two(d.day)}-${_two(d.month)}-${_two(d.year % 100)}';
String _t(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;
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
  });
  tearDown(() => db.close());

  test('SMS then email of one payment → one row, two sources', () async {
    final at = DateTime(2026, 10, 2, 21, 36, 2);
    expect(await ingest.ingest(sms(25, at)), IngestOutcome.transaction);
    expect(await ingest.ingest(email(25, at)), IngestOutcome.merged);
    final rows = await ledger.watchTransactions(oct).first;
    expect(rows, hasLength(1));
    expect(rows.single.sourceCount, 2);
    expect(rows.single.merged, isTrue);
  });

  test('email first, SMS later also merges', () async {
    final at = DateTime(2026, 10, 2, 21, 36, 2);
    expect(await ingest.ingest(email(25, at)), IngestOutcome.transaction);
    expect(
      await ingest.ingest(sms(25, at.add(const Duration(minutes: 4)))),
      IngestOutcome.merged,
    );
    expect(await ledger.watchTransactions(oct).first, hasLength(1));
  });

  test('two SMS for the same amount stay two payments', () async {
    final at = DateTime(2026, 10, 2, 21, 36, 2);
    await ingest.ingest(sms(25, at));
    await ingest.ingest(
      sms(25, at.add(const Duration(minutes: 1)), ref: '441151550999'),
    );
    expect(await ledger.watchTransactions(oct).first, hasLength(2));
  });

  test('outside the window, or a different amount, stays separate', () async {
    final at = DateTime(2026, 10, 2, 21, 36, 2);
    await ingest.ingest(sms(25, at));
    await ingest.ingest(email(25, at.add(const Duration(minutes: 30))));
    await ingest.ingest(email(26, at));
    expect(await ledger.watchTransactions(oct).first, hasLength(3));
  });

  test('one email pairs with only one SMS', () async {
    final at = DateTime(2026, 10, 2, 21, 36, 2);
    await ingest.ingest(sms(25, at));
    await ingest.ingest(
      sms(25, at.add(const Duration(minutes: 2)), ref: '441151550999'),
    );
    await ingest.ingest(email(25, at));
    final rows = await ledger.watchTransactions(oct).first;
    expect(rows, hasLength(2));
    expect(rows.where((r) => r.merged), hasLength(1));
  });

  test('bank email with no amount skips Review; SMS without one does not', () async {
    final at = DateTime(2026, 10, 3, 22, 18);
    expect(
      await ingest.ingest(
        IncomingMessage(
          channel: Channel.email,
          sender: 'statements@axis.bank.in',
          subject: 'AXIS BANK : Statement for September 2026',
          body:
              'Dear Customer,\nYour Combined Email Statement for the month of '
              'September 2026 is attached below.',
          receivedAt: at,
        ),
      ),
      IngestOutcome.nonTransaction,
    );
    expect(
      await ingest.ingest(
        IncomingMessage(
          channel: Channel.sms,
          sender: 'AX-AXISBK-S',
          body: 'Your A/c XX0640 statement for Sep is ready. Axis Bank',
          receivedAt: at,
        ),
      ),
      IngestOutcome.needsReview,
    );
  });
}
