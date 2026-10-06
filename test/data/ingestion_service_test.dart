import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart';
import 'package:k/data/db/enums.dart';
import 'package:k/data/ingest/category_resolver.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:txn_parser/txn_parser.dart';

IncomingMessage sms(String sender, String body, DateTime at) => IncomingMessage(
  channel: Channel.sms,
  sender: sender,
  body: body,
  receivedAt: at,
);

final axisUpi = sms(
  'AX-AXISBK-S',
  'INR 412.00 debited\nA/c no. XX1234\n05-10-26, 10:48:12\n'
      'UPI/P2M/298833881599/ZEPTO MARKETPLACE PR\n'
      'Not you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank',
  DateTime(2026, 10, 5, 10, 48, 20),
);

final axisCard = sms(
  'AX-AXISBK-T',
  'Spent INR 1,299\nAxis Bank Card no. XX5678\n04-10-26 20:11:45 IST\n'
      'AMAZON PAY IN E\nAvl Limit: INR 85,420.50\n'
      'Not you? SMS BLOCK 5678 to 919951860002',
  DateTime(2026, 10, 4, 20, 12),
);

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;

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

  test(
    'UPI debit becomes a categorized transaction on a new account',
    () async {
      expect(await ingest.ingest(axisUpi), IngestOutcome.transaction);

      final txns = await ledger
          .watchTransactions(TxnFilter.month(DateTime(2026, 10)))
          .first;
      expect(txns, hasLength(1));
      final t = txns.single;
      expect(t.amountMinor, 41200);
      expect(t.direction, Direction.debit);
      expect(t.txnType, TxnType.upi);
      expect(t.payee, 'Zepto Marketplace PR');
      expect(t.category?.id, 'cat_groceries');
      expect(t.account?.short, 'Axis ··1234');
      expect(t.account?.type, AccountType.savings);
      expect(t.sourceCount, 1);

      final raw = await db.select(db.rawMessages).getSingle();
      expect(raw.status, RawMessageStatus.parsed);
      expect(raw.bankId, 'AXIS');
    },
  );

  test('card spend with a limit lands on a credit card account', () async {
    await ingest.ingest(axisCard);
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals('acc_cash').not())).getSingle();
    expect(account.type, AccountType.creditCard);
    expect(account.last4, '5678');
    expect(account.autoCreated, isTrue);
    final txn = await db.select(db.transactions).getSingle();
    expect(txn.balanceMinor, 8542050);
    expect(txn.categoryId, 'cat_shopping');
  });

  test('same message twice is stored once', () async {
    await ingest.ingest(axisUpi);
    expect(await ingest.ingest(axisUpi), IngestOutcome.duplicate);
    // Inbox copy with a slightly different timestamp is the same SMS.
    final late = sms(
      axisUpi.sender,
      axisUpi.body,
      axisUpi.receivedAt.add(const Duration(seconds: 40)),
    );
    expect(await ingest.ingest(late), IngestOutcome.duplicate);
    expect(await db.rawMessages.count().getSingle(), 1);
    expect(await db.transactions.count().getSingle(), 1);
  });

  test('second payment to the same account and merchant reuses both', () async {
    await ingest.ingest(axisUpi);
    await ingest.ingest(
      sms(
        axisUpi.sender,
        axisUpi.body.replaceFirst('412.00', '99.00'),
        DateTime(2026, 10, 6, 9),
      ),
    );
    expect(
      (await db.select(db.accounts).get())
          .where((a) => a.id != 'acc_cash')
          .length,
      1,
    );
    expect(await db.merchants.count().getSingle(), 1);
    expect(await db.transactions.count().getSingle(), 2);
  });

  test('personal or unknown sender is dropped without storing', () async {
    final outcome = await ingest.ingest(
      sms('VM-SWIGGY', 'Your order is on the way', DateTime(2026, 10, 5)),
    );
    expect(outcome, IngestOutcome.notBank);
    expect(await db.rawMessages.count().getSingle(), 0);
  });

  test('OTP is stored for the trail but not logged', () async {
    final outcome = await ingest.ingest(
      sms(
        'AX-AXISBK-S',
        '123456 is the OTP for transaction of INR 1,299.00 at AMAZON on Axis '
            'Bank card XX5678. Valid for 10 mins. Do not share OTP for '
            'security reasons.',
        DateTime(2026, 10, 4, 20, 10),
      ),
    );
    expect(outcome, IngestOutcome.nonTransaction);
    expect(await db.transactions.count().getSingle(), 0);
  });

  test('unknown format goes to review', () async {
    final outcome = await ingest.ingest(
      sms(
        'AX-AXISBK-S',
        'Your a/c XX1234 has been debited for Rs 99 towards SOMETHING NEW ref '
            'no 88776655. Axis Bank',
        DateTime(2026, 10, 3, 13),
      ),
    );
    expect(outcome, IngestOutcome.needsReview);
    expect(await ledger.watchReviewCount().first, 1);
    expect(await db.transactions.count().getSingle(), 0);
  });

  test('mandate alert becomes an upcoming charge', () async {
    final outcome = await ingest.ingest(
      sms(
        'JD-KOTAKB-S',
        'Upcoming debit: Rs.649.00 will be debited from your Kotak Bank AC '
            'X1234 on 08-10-26 towards NETFLIX for UPI-Mandate. '
            'UMN: KKBK0001234567890',
        DateTime(2026, 10, 6, 9),
      ),
    );
    expect(outcome, IngestOutcome.upcoming);
    final upcoming = await ledger.watchUpcoming(DateTime(2026, 10, 6)).first;
    expect(upcoming.single.name, 'Netflix');
    expect(upcoming.single.amountMinor, 64900);
    expect(upcoming.single.bankShort, 'Kotak');
    expect(await db.transactions.count().getSingle(), 0);
  });

  test('filters, search and removal', () async {
    await ingest.ingest(axisUpi);
    await ingest.ingest(axisCard);
    final oct = TxnFilter.month(DateTime(2026, 10));

    final shopping = await ledger
        .watchTransactions(oct.copyWith(categoryIds: {'cat_shopping'}))
        .first;
    expect(shopping.single.payee, 'Amazon Pay In E');

    final search = await ledger
        .watchTransactions(oct.copyWith(query: 'zepto'))
        .first;
    expect(search, hasLength(1));

    final sept = await ledger
        .watchTransactions(TxnFilter.month(DateTime(2026, 9)))
        .first;
    expect(sept, isEmpty);

    final id = search.single.id;
    await ledger.removeTransaction(id, notATransaction: true);
    expect(await ledger.watchTransactions(oct).first, hasLength(1));
    final raw =
        await (db.select(db.rawMessages)..where(
              (r) => r.status.equalsValue(RawMessageStatus.nonTransaction),
            ))
            .get();
    expect(raw, hasLength(1));
  });

  test('detail lists the source message', () async {
    await ingest.ingest(axisCard);
    final txn = await db.select(db.transactions).getSingle();
    final detail = await ledger.watchDetail(txn.id).first;
    expect(detail!.sources.single.sender, 'AX-AXISBK-T');
    expect(detail.txn.account?.long, 'Axis credit card ··5678');
  });

  group('CategoryResolver', () {
    CategoryRule kw(String p, String c, {int priority = 0}) => CategoryRule(
      id: p,
      matchType: RuleMatchType.keyword,
      pattern: p,
      categoryId: c,
      priority: priority,
      origin: RuleOrigin.system,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    final resolver = CategoryResolver([
      kw('jio', 'cat_bills'),
      kw('jiomart', 'cat_groceries'),
      kw('zepto', 'cat_groceries'),
      kw('ola', 'cat_travel'),
    ]);

    test('longest keyword wins, on word boundaries', () {
      expect(resolver.resolve(payee: 'JIOMART ONLINE'), 'cat_groceries');
      expect(resolver.resolve(payee: 'Reliance Jio'), 'cat_bills');
      expect(resolver.resolve(payee: 'COLA STORE'), uncategorizedId);
    });

    test('VPA handles match glued keywords', () {
      expect(
        resolver.resolve(payee: 'zeptonowcashfree@hdfcbank'),
        'cat_groceries',
      );
    });
  });

  test('merchantDisplayName', () {
    expect(merchantDisplayName('IRCTC', 'irctc'), 'IRCTC');
    expect(merchantDisplayName('DMRC', 'dmrc'), 'DMRC');
    expect(merchantDisplayName('swiggy.upi@axb', 'swiggy'), 'Swiggy');
    expect(merchantDisplayName('Rahul Sharma', 'rahul sharma'), 'Rahul Sharma');
  });
}
