import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/db/enums.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/ingest/unknown_sender.dart';
import 'package:k/data/repositories/bank_repository.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/review/field_marks.dart';
import 'package:k/data/review/review_service.dart';
import 'package:txn_parser/txn_parser.dart';

IncomingMessage sms(String sender, String body, DateTime at) => IncomingMessage(
  channel: Channel.sms,
  sender: sender,
  body: body,
  receivedAt: at,
);

String zz(String amount, String payee, String ref, String date) =>
    'Your A/c XX7720 is debited for Rs $amount to $payee UPI Ref $ref on '
    '$date. -ZZ Bank';

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late BankRepository banks;
  late ReviewService review;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ingest = IngestionService(db);
    banks = BankRepository(db, onRulesChanged: ingest.invalidate);
    review = ReviewService(
      db,
      ingest,
      LedgerRepository(db, onRulesChanged: ingest.invalidate),
      banks,
    );
  });
  tearDown(() => db.close());

  Future<List<RawMessage>> raws() => db.select(db.rawMessages).get();

  /// Marks every field the ZZ Bank sample carries.
  List<FieldMark> marksFor(ReviewItem item) {
    FieldMark at(MarkField f, String v) {
      final i = item.text.indexOf(v);
      return FieldMark(f, i, i + v.length);
    }

    return [
      at(MarkField.account, '7720'),
      at(MarkField.direction, 'debited'),
      at(MarkField.amount, '450.00'),
      at(MarkField.payee, 'SWIGGY'),
      at(MarkField.ref, '427812345678'),
    ];
  }

  test('sender core drops operator prefix and suffix', () {
    expect(senderCore('JD-HDFCBK-S'), 'HDFCBK');
    expect(senderCore('VM-HDFCBK'), 'HDFCBK');
    expect(senderCore('HDFCBK'), 'HDFCBK');
    expect(bankCodeFor('ZZ Bank'), 'ZZ');
    expect(bankCodeFor('State Bank of India'), 'STATE_INDIA');
  });

  test('payment-like SMS from an unknown sender waits in Review', () async {
    final out = await ingest.ingest(
      sms(
        'JD-ZZBANK-S',
        zz('450.00', 'SWIGGY', '427812345678', '04-10-26'),
        DateTime(2026, 10, 4, 19, 40),
      ),
    );
    expect(out, IngestOutcome.needsReview);
    final item = (await review.watchQueue().first).single;
    expect(item.unknownSender, isTrue);
    expect(item.bankId, isNull);
    expect(item.guess.fields.amountMinor, 45000);
    expect(item.reason, startsWith('New sender'));
  });

  test('chatter, OTPs and promos from unknown senders are dropped', () async {
    final at = DateTime(2026, 10, 4);
    for (final body in [
      'Your order is out for delivery. Track at example.com',
      '482913 is your OTP for login. Do not share it.',
      'Get up to Rs 500 cashback! Apply now on our app.',
    ]) {
      expect(
        await ingest.ingest(sms('VM-SHOPZZ', body, at)),
        IngestOutcome.notBank,
      );
    }
    expect(await raws(), isEmpty);
  });

  test(
    'naming a new bank adds it, learns the format, reads the next one',
    () async {
      await ingest.ingest(
        sms(
          'JD-ZZBANK-S',
          zz('450.00', 'SWIGGY', '427812345678', '04-10-26'),
          DateTime(2026, 10, 4, 19, 40),
        ),
      );
      final item = (await review.watchQueue().first).single;
      final result = await review.save(
        item,
        ReviewDraft(
          marks: marksFor(item),
          direction: Direction.debit,
          bank: const BankChoice.create('ZZ Bank', emailSender: 'zzbank.in'),
        ),
      );
      expect(result.learned, isTrue, reason: result.learnError);

      final bank = await (db.select(
        db.banks,
      )..where((b) => b.id.equals('ZZ'))).getSingle();
      expect(bank.name, 'ZZ Bank');
      final rules = await (db.select(
        db.senderRules,
      )..where((r) => r.bankId.equals('ZZ'))).get();
      expect({for (final r in rules) r.pattern}, {'ZZBANK', 'zzbank.in'});

      final txn = await db.select(db.transactions).getSingle();
      expect(txn.amountMinor, 45000);
      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(txn.accountId!))).getSingle();
      expect(account.bankId, 'ZZ');
      expect(account.last4, '7720');

      // Another operator prefix, same bank: read on its own now.
      final next = await ingest.ingest(
        sms(
          'VM-ZZBANK-T',
          zz('120.00', 'ZEPTO', '427812349999', '05-10-26'),
          DateTime(2026, 10, 5, 9),
        ),
      );
      expect(next, IngestOutcome.transaction);
    },
  );

  test('other waiting messages from the sender take the bank', () async {
    await ingest.ingest(
      sms(
        'JD-ZZBANK-S',
        zz('450.00', 'SWIGGY', '427812345678', '04-10-26'),
        DateTime(2026, 10, 4, 19, 40),
      ),
    );
    await ingest.ingest(
      sms(
        'JD-ZZBANK-S',
        'Rs 99.00 spent on ZZ card ending 1111 at FUELSTOP. -ZZ Bank',
        DateTime(2026, 10, 4, 20),
      ),
    );
    final queue = await review.watchQueue().first;
    final first = queue.firstWhere((i) => i.text.contains('SWIGGY'));
    await review.save(
      first,
      ReviewDraft(
        marks: marksFor(first),
        direction: Direction.debit,
        bank: const BankChoice.create('ZZ Bank'),
      ),
    );
    final left = (await review.watchQueue().first).single;
    expect(left.text, contains('FUELSTOP'));
    expect(left.bankId, 'ZZ');
    expect(left.unknownSender, isFalse);
  });

  test('not a bank blocks the sender; undo lets it back', () async {
    final at = DateTime(2026, 10, 4, 19, 40);
    await ingest.ingest(
      sms('JD-ZZBANK-S', zz('450.00', 'SWIGGY', '1', '04-10-26'), at),
    );
    final item = (await review.watchQueue().first).single;
    final undo = await review.notABank(item);
    expect(await review.watchQueue().first, isEmpty);
    expect(
      await ingest.ingest(
        sms('JD-ZZBANK-S', zz('10.00', 'X', '2', '05-10-26'), at),
      ),
      IngestOutcome.notBank,
    );

    await review.undo(undo);
    expect(await review.watchQueue().first, hasLength(1));
    expect(
      await ingest.ingest(
        sms('JD-ZZBANK-S', zz('11.00', 'Y', '3', '06-10-26'), at),
      ),
      IngestOutcome.needsReview,
    );
  });

  test(
    'not a transaction + skip similar learns a skip format; undo forgets it',
    () async {
      String notice(String d) =>
          'Your Axis Bank statement for $d is ready. Rs 0.00 due. Axis Bank';
      for (final (i, d) in ['09-2026', '08-2026'].indexed) {
        await ingest.ingest(
          IncomingMessage(
            channel: Channel.sms,
            sender: 'AX-AXISBK-S',
            body: notice(d),
            receivedAt: DateTime(2026, 10, 1 + i),
          ),
        );
      }
      final queue = await review.watchQueue().first;
      expect(queue, hasLength(2));
      final undo = await review.notATransaction(queue.first, skipSimilar: true);
      expect(undo.templateId, isNotNull);
      expect(undo.rawIds, hasLength(2));
      expect(await review.watchQueue().first, isEmpty);
      final template = await db.select(db.parserTemplates).getSingle();
      expect(template.kind, TemplateKind.ignore);

      await review.undo(undo);
      expect(await review.watchQueue().first, hasLength(2));
      final forgotten = await db.select(db.parserTemplates).getSingle();
      expect(forgotten.deletedAt, isNotNull);
    },
  );

  test('an AutoPay alert saved from Review becomes an upcoming charge and '
      'teaches the format', () async {
    String alert(String amount, String payee, String due) =>
        'E-mandate: Rs $amount for $payee will be auto-debited on $due from '
        'A/c XX1234. Keep sufficient balance. Axis Bank';
    await ingest.ingest(
      IncomingMessage(
        channel: Channel.sms,
        sender: 'AX-AXISBK-S',
        body: alert('195.00', 'APPLE MEDIA SERVICES', '29-09-2026'),
        receivedAt: DateTime(2026, 9, 26, 10, 15),
      ),
    );
    final item = (await review.watchQueue().first).single;
    FieldMark at(MarkField f, String v) {
      final i = item.text.indexOf(v);
      return FieldMark(f, i, i + v.length);
    }

    final result = await review.save(
      item,
      ReviewDraft(
        marks: [
          at(MarkField.amount, '195.00'),
          at(MarkField.payee, 'APPLE MEDIA SERVICES'),
          at(MarkField.dueDate, '29-09-2026'),
        ],
        direction: Direction.debit,
        kind: TemplateKind.mandate,
      ),
    );
    expect(result.learned, isTrue, reason: result.learnError);
    final charge = await db.select(db.upcomingCharges).getSingle();
    expect(charge.amountMinor, 19500);
    expect(charge.dueDate, DateTime(2026, 9, 29));
    expect(await db.select(db.transactions).get(), isEmpty);

    final next = await ingest.ingest(
      IncomingMessage(
        channel: Channel.sms,
        sender: 'AX-AXISBK-S',
        body: alert('649.00', 'NETFLIX', '08-10-2026'),
        receivedAt: DateTime(2026, 10, 5, 10),
      ),
    );
    expect(next, IngestOutcome.upcoming);
    final status = (await raws()).map((r) => r.status).toSet();
    expect(status, {RawMessageStatus.parsed});
  });

  test(
    'a sender named as a catalogue wallet logs to a wallet account',
    () async {
      await ingest.ingest(
        sms(
          'VM-PHONPE-S',
          'Paid Rs 120.00 to SWIGGY from your PhonePe wallet. Txn ID T2610041',
          DateTime(2026, 10, 4, 13),
        ),
      );
      final item = (await review.watchQueue().first).single;
      FieldMark at(MarkField f, String v) {
        final i = item.text.indexOf(v);
        return FieldMark(f, i, i + v.length);
      }

      await review.save(
        item,
        ReviewDraft(
          marks: [
            at(MarkField.amount, '120.00'),
            at(MarkField.payee, 'SWIGGY'),
          ],
          direction: Direction.debit,
          bank: const BankChoice.existing('PHONEPE'),
        ),
      );
      final txn = await db.select(db.transactions).getSingle();
      final account = await (db.select(
        db.accounts,
      )..where((a) => a.id.equals(txn.accountId!))).getSingle();
      expect(account.bankId, 'PHONEPE');
      expect(account.type, AccountType.wallet);
    },
  );
}
