// QA audit: ingestion, dedup and linker edge cases that cost money.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/ingest/offset_linker.dart';
import 'package:k/data/ingest/transfer_linker.dart';
import 'package:txn_parser/txn_parser.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _d(DateTime d) =>
    '${_two(d.day)}-${_two(d.month)}-${_two(d.year % 100)}';
String _t(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// Axis UPI debit SMS (synthetic, masked).
IncomingMessage axisSms(int rupees, DateTime at, {required String ref}) =>
    IncomingMessage(
      channel: Channel.sms,
      sender: 'AX-AXISBK-S',
      body:
          'INR $rupees.00 debited\nA/c no. XX1111\n'
          '${_d(at)}, ${_t(at)}\nUPI/P2M/$ref/TEST SHOP\n'
          'Not you? SMS BLOCKUPI Cust ID to 910000000000\nAxis Bank',
      receivedAt: at,
    );

/// Axis UPI debit alert email (synthetic, masked).
IncomingMessage axisEmail(int rupees, DateTime at, {required String ref}) =>
    IncomingMessage(
      channel: Channel.email,
      sender: 'Axis Bank <alerts@axis.bank.in>',
      subject: 'INR $rupees.00 was debited from your A/c no. XX1111',
      body:
          '${_d(at)}\nDear Customer,\n\nHere\'s the summary of your '
          'transaction:\n\n\nAccount Number:\nXX1111\n\nDate & Time:\n'
          '${_d(at)}, ${_t(at)} IST\n\nTransaction Info:\n'
          'UPI/P2M/$ref/TEST SHOP\n\nRegards,\nAxis Bank Ltd.\n',
      receivedAt: at.add(const Duration(minutes: 1)),
    );

/// Kotak UPI credit SMS into AC 5555 (synthetic).
IncomingMessage kotakIn(int rupees, DateTime at) => IncomingMessage(
  channel: Channel.sms,
  sender: 'JD-KOTAKB-S',
  body:
      'Received Rs.$rupees.00 in your Kotak Bank AC 5555 from TEST PERSON on '
      '${_d(at)}.UPI Ref:12345678${_two(at.minute)}${_two(at.hour)}',
  receivedAt: at,
);

void main() {
  late AppDatabase db;
  late IngestionService ingest;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ingest = IngestionService(db);
  });
  tearDown(() => db.close());

  Future<List<Transaction>> live() =>
      (db.select(db.transactions)..where((t) => t.deletedAt.isNull())).get();

  test('SMS and email with different UPI refs are two payments, '
      'not one merged row', () async {
    final at = DateTime(2026, 10, 2, 21, 36, 2);
    // Payment A only alerted by SMS, payment B only by email (e.g. the
    // other alert was lost) — same account, same amount, minutes apart.
    expect(
      await ingest.ingest(axisSms(250, at, ref: '600000000001')),
      IngestOutcome.transaction,
    );
    final second = await ingest.ingest(
      axisEmail(250, at.add(const Duration(minutes: 3)), ref: '600000000002'),
    );
    expect(second, IngestOutcome.transaction);
    expect(await live(), hasLength(2));
  });

  test(
    'a credit already cancelling out is not stolen as a transfer side',
    () async {
      final at = DateTime(2026, 10, 2, 10);
      // ₹500 came in on Kotak and was marked as cancelling out with a ₹500
      // the owner paid (a friend paying back their share).
      await ingest.ingest(kotakIn(500, at));
      final credit = (await live()).single;
      final paid = await ingest.addManual(
        direction: Direction.debit,
        amountMinor: 50000,
        occurredAt: at.subtract(const Duration(hours: 1)),
      );
      await OffsetLinker(db).link(paid, credit.id);

      // An unrelated ₹500 Axis debit 5 minutes later.
      await ingest.ingest(
        axisSms(500, at.add(const Duration(minutes: 5)), ref: '600000000003'),
      );

      final after = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(credit.id))).getSingle();
      expect(after.offsetId, isNotNull);
      expect(
        after.transferId,
        isNull,
        reason: 'a row in a cancel-out group must not also be a transfer',
      );
    },
  );

  test('"Mark as self transfer" with an added side, tapped twice, adds '
      'one side only', () async {
    final at = DateTime(2026, 10, 2, 10);
    await ingest.ingest(kotakIn(100, DateTime(2026, 9, 1, 9)));
    await ingest.ingest(axisSms(5000, at, ref: '600000000004'));
    final kotak = await (db.select(
      db.accounts,
    )..where((a) => a.last4.equals('5555'))).getSingle();
    final out = (await live()).firstWhere((t) => t.amountMinor == 500000);

    final linker = TransferLinker(db);
    await Future.wait([
      linker.markManual(out.id, addOnAccountId: kotak.id),
      linker.markManual(out.id, addOnAccountId: kotak.id),
    ]);

    final onKotak = (await live())
        .where((t) => t.accountId == kotak.id && t.amountMinor == 500000)
        .toList();
    expect(
      onKotak,
      hasLength(1),
      reason: 'a second added side inflates Kotak\'s balance by ₹5,000',
    );
    final sides = (await live()).where((t) => t.transferId != null).toList();
    expect(sides, hasLength(2));
    expect(sides.map((t) => t.transferId).toSet(), hasLength(1));
  });

  test('a review item saved twice (double tap / re-check race) logs once '
      'and does not throw', () async {
    final at = DateTime(2026, 10, 2, 12);
    expect(
      await ingest.ingest(
        IncomingMessage(
          channel: Channel.sms,
          sender: 'AX-AXISBK-S',
          body:
              'Your a/c XX1111 has been debited for Rs 700 towards TEST SHOP '
              'ref no 700000000001. Axis Bank',
          receivedAt: at,
        ),
      ),
      IngestOutcome.needsReview,
    );
    final raw = await db.select(db.rawMessages).getSingle();
    final fields = ParsedFields(
      amountMinor: 70000,
      direction: Direction.debit,
      last4: '1111',
      payee: 'TEST SHOP',
      occurredAt: at,
    );
    await Future.wait([
      ingest.logReviewed(raw, fields),
      ingest.logReviewed(raw, fields),
    ]);
    expect(await live(), hasLength(1));
  });

  test(
    'an AutoPay alert saved twice from review is one upcoming charge',
    () async {
      final at = DateTime(2026, 10, 2, 12);
      await ingest.ingest(
        IncomingMessage(
          channel: Channel.sms,
          sender: 'AX-AXISBK-S',
          body:
              'Your a/c XX1111 has been debited for Rs 199 towards TEST STREAM '
              'ref no 700000000002. Axis Bank',
          receivedAt: at,
        ),
      );
      final raw = await db.select(db.rawMessages).getSingle();
      final fields = ParsedFields(
        amountMinor: 19900,
        payee: 'TEST STREAM',
        dueDate: DateTime(2026, 10, 5),
      );
      // Sequential: the second save comes after the first finished.
      await ingest.logReviewed(raw, fields, kind: TemplateKind.mandate);
      final again = await db.select(db.rawMessages).getSingle();
      await ingest.logReviewed(again, fields, kind: TemplateKind.mandate);
      expect(await db.select(db.upcomingCharges).get(), hasLength(1));
    },
  );
}
