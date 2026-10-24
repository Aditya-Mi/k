import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart';
import 'package:k/data/db/enums.dart';
import 'package:k/data/emis/emi_schedule.dart';
import 'package:k/data/emis/emi_service.dart';
import 'package:k/data/ingest/card_bill.dart';
import 'package:k/data/ingest/transfer_linker.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/repositories/settings_repository.dart';
import 'package:k/data/summary/month_report.dart';
import 'package:k/ui/screens/transactions/transactions_cubit.dart';
import 'package:txn_parser/txn_parser.dart';

IncomingMessage sms(String sender, String body, DateTime at) => IncomingMessage(
  channel: Channel.sms,
  sender: sender,
  body: body,
  receivedAt: at,
);

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.year % 100}';
String _t(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';

/// Axis UPI debit from savings XX1111.
IncomingMessage axisOut(int rupees, DateTime at, {required String payee}) =>
    sms(
      'AX-AXISBK-S',
      'INR $rupees.00 debited\nA/c no. XX1111\n'
          '${_d(at)}, ${_t(at)}\nUPI/P2M/1000000000${at.minute}/$payee\n'
          'Not you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank',
      at,
    );

/// Axis credit card XX5678 spend.
IncomingMessage cardSpend(int rupees, DateTime at, {String at_ = 'AMAZON'}) =>
    sms(
      'AX-AXISBK-T',
      'Spent INR $rupees\nAxis Bank Card no. XX5678\n'
          '${_d(at)} ${_t(at)} IST\n$at_\nAvl Limit: INR 85,420.50\n'
          'Not you? SMS BLOCK 5678 to 919951860002',
      at,
    );

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;
  late EmiService emis;
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
    emis = EmiService(db, SettingsRepository(db));
  });
  tearDown(() => db.close());

  Future<List<TxnView>> txns([TxnFilter? f]) =>
      ledger.watchTransactions(f ?? oct).first;

  Future<String> cardId() async => (await (db.select(
    db.accounts,
  )..where((a) => a.last4.equals('5678'))).getSingle()).id;

  test('looksLikeCardBill: CRED, credit card, CC payment; not shopping', () {
    expect(looksLikeCardBill('CRED Club', ''), isTrue);
    expect(looksLikeCardBill(null, 'Payment to Credit Card XX5678'), isTrue);
    expect(looksLikeCardBill('BILLDESK CC PAYMENT', ''), isTrue);
    expect(looksLikeCardBill('Credence Stores', ''), isFalse);
    expect(looksLikeCardBill('AMAZON', 'debited A/c XX1111'), isFalse);
    // Card boilerplate in a message is not a bill payment.
    expect(
      looksLikeCardBill('SWIGGY', 'Not you? Call us to block your credit card'),
      isFalse,
    );
    expect(
      looksLikeCardBill('ZEPTO', 'Get a lifetime free Credit Card. Apply now'),
      isFalse,
    );
    expect(maskedDigits('to card XX5678 from XX1111', own: '1111'), {'5678'});
  });

  test(
    'a credit card saved as a debit card comes out with its spends',
    () async {
      await ingest.ingest(
        axisOut(200, DateTime(2026, 10, 1, 9), payee: 'Chai Point'),
      );
      final savings = (await txns()).single.account!;
      // Owner took ··5678 for the savings account's debit card.
      expect(await ledger.addDebitCard(savings.id, '5678'), isTrue);
      await ingest.ingest(cardSpend(1299, DateTime(2026, 10, 2, 12)));
      expect((await txns()).map((t) => t.account!.id).toSet(), {savings.id});
      // Its available limit isn't the savings account's balance.
      expect(
        (await txns())
            .where((t) => t.amountMinor == 129900)
            .single
            .balanceMinor,
        isNull,
      );
      // Adding it as a credit card hits the folded row.
      expect(
        await ledger.addAccount(
          bankId: 'AXIS',
          type: AccountType.creditCard,
          last4: '5678',
        ),
        isNull,
      );
      final folded = await ledger.findAccount('AXIS', '5678');
      expect(folded!.mergedIntoId, savings.id);
      expect((await ledger.cardsIn(savings.id)).single.id, folded.id);

      await ingest.separateCard(folded.id, AccountType.creditCard);

      final card = (await ledger.watchAccounts().first)
          .where((a) => a.last4 == '5678')
          .single;
      expect(card.isCreditCard, isTrue);
      final rows = await txns();
      expect(
        rows.where((t) => t.amountMinor == 129900).single.account!.id,
        card.id,
      );
      expect(
        rows.where((t) => t.amountMinor == 20000).single.account!.id,
        savings.id,
      );
      // Later spends land on the card too.
      await ingest.ingest(cardSpend(500, DateTime(2026, 10, 3, 12)));
      expect((await txns()).where((t) => t.account!.id == card.id).length, 2);
    },
  );

  test('with two cards, a bill goes to the card the owner picks', () async {
    await ingest.ingest(cardSpend(1299, DateTime(2026, 10, 1, 12)));
    final other = await ledger.addAccount(
      bankId: 'AXIS',
      type: AccountType.creditCard,
      last4: '4321',
    );
    await ingest.ingest(
      axisOut(5000, DateTime(2026, 10, 5, 10), payee: 'Ramesh Kumar'),
    );
    final bill = (await txns()).firstWhere((t) => t.amountMinor == 500000);
    expect(bill.isTransfer, isFalse);
    await TransferLinker(db).markCardBill(bill.id, force: true, cardId: other);
    final rows = await txns();
    final paid = rows.firstWhere((t) => t.id == bill.id);
    expect(paid.isCardBill, isTrue);
    expect(paid.partnerAccount?.id, other);
    expect(summarize(oct.from, rows).spentMinor, 129900);
  });

  test('a payment moves to another account', () async {
    await ingest.ingest(
      axisOut(200, DateTime(2026, 10, 1, 9), payee: 'Chai Point'),
    );
    await ingest.ingest(cardSpend(1299, DateTime(2026, 10, 2, 12)));
    final rows = await txns();
    final spend = rows.firstWhere((t) => t.account!.isCreditCard);
    final savings = rows.firstWhere((t) => !t.account!.isCreditCard).account!;
    await ledger.moveTransaction(spend.id, savings.id);
    expect((await txns()).map((t) => t.account!.id).toSet(), {savings.id});
  });

  test('with no card in k, a CRED payment stays a payment', () async {
    await ingest.ingest(
      axisOut(12300, DateTime(2026, 10, 2, 10, 4), payee: 'CRED Club'),
    );
    final rows = await txns();
    expect(rows.single.isCardBill, isFalse);
    expect(rows.single.isTransfer, isFalse);
    expect(summarize(oct.from, rows).spentMinor, 1230000);
  });

  test('paying the card bill from savings is not spent', () async {
    await ingest.ingest(cardSpend(1299, DateTime(2026, 10, 1, 12)));
    await ingest.ingest(
      axisOut(12300, DateTime(2026, 10, 2, 10, 4), payee: 'CRED Club'),
    );
    final rows = (await txns()).where((r) => r.isDebit && r.isCardBill);
    expect(rows.single.isCardBill, isTrue);
    expect(rows.single.countsInTotals, isFalse);
    expect(rows.single.category?.id, cardBillCategoryId);
    expect(rows.single.category?.id, cardBillCategoryId);
  });

  test('with the card in k, a bill payment adds the card side', () async {
    await ingest.ingest(cardSpend(1299, DateTime(2026, 10, 1, 12)));
    await ingest.ingest(
      axisOut(12300, DateTime(2026, 10, 2, 10, 4), payee: 'CRED Club'),
    );
    final bill = (await txns()).where((r) => r.isCardBill).toList();
    expect(bill, hasLength(2));
    expect(bill.first.transferId, bill.last.transferId);
    final credit = bill.firstWhere((r) => !r.isDebit);
    expect(credit.account?.last4, '5678');
    expect(credit.addedByUser, isTrue);
    expect(credit.isRefund, isFalse);
  });

  test(
    'a bill paid before the card was in k is picked up once it is',
    () async {
      await ingest.ingest(
        axisOut(12300, DateTime(2026, 10, 2, 10, 4), payee: 'CRED Club'),
      );
      expect((await txns()).single.isCardBill, isFalse);
      await ingest.ingest(cardSpend(1299, DateTime(2026, 10, 2, 12)));
      // Start-up backfill.
      await TransferLinker(db).markCardBillsAll();
      final bill = (await txns()).where((r) => r.isCardBill).toList();
      expect(bill, hasLength(2));
      expect(bill.first.transferId, bill.last.transferId);
      final credit = bill.firstWhere((r) => !r.isDebit);
      expect(credit.account?.last4, '5678');
      expect(credit.partnerAccount?.last4, '1111');
    },
  );

  test('1.1.0 false card bills go back to payments, once', () async {
    final linker = TransferLinker(db);
    await ingest.ingest(
      axisOut(41200, DateTime(2026, 10, 2, 10, 4), payee: 'ZEPTO'),
    );
    final id = (await txns()).single.id;
    // What 1.1.0 did: marked it a lone card bill (email boilerplate).
    await linker.markCardBill(id, force: true);
    expect((await txns()).single.isCardBill, isTrue);

    await linker.markCardBillsAll();
    final row = (await txns()).single;
    expect(row.isCardBill, isFalse);
    expect(row.isTransfer, isFalse);
    expect(row.category?.id, isNot(cardBillCategoryId));

    // Runs once: a bill the owner marks afterwards stays.
    await linker.markCardBill(id, force: true);
    await linker.markCardBillsAll();
    expect((await txns()).single.isCardBill, isTrue);
  });

  test('card refunds lower spent; they are not money in', () async {
    await ingest.ingest(cardSpend(1299, DateTime(2026, 10, 4, 20)));
    await ingest.addManual(
      direction: Direction.credit,
      amountMinor: 49900,
      occurredAt: DateTime(2026, 10, 5, 11),
      accountId: await cardId(),
      payee: 'AMAZON',
    );
    final rows = await txns();
    expect(rows.where((r) => r.isRefund), hasLength(1));
    final s = summarize(oct.from, rows);
    expect(s.spentMinor, 129900 - 49900);
    expect(s.inMinor, 0);
    expect(s.spends, 1);
    final report = MonthReport.build(oct.from, rows);
    expect(report.spentMinor, 80000);
    expect(report.inMinor, 0);
  });

  test('owed is the limit minus available', () {
    const card = AccountView(
      id: 'c',
      bankId: 'AXIS',
      bankName: 'Axis Bank',
      type: AccountType.creditCard,
      creditLimitMinor: 10000000,
    );
    expect(card.owedMinor(8542050), 1457950);
    expect(card.owedMinor(null), isNull);
    expect(card.owedMinor(10500000), 0);
  });

  group('EMI', () {
    test('schedule: clamps month ends, counts paid, rebuilds the first', () {
      expect(addMonths(DateTime(2027, 1, 31), 1), DateTime(2027, 2, 28));
      final s = EmiSchedule(
        firstDueAt: DateTime(2026, 11, 3),
        count: 12,
        amountMinor: 333000,
      );
      expect(s.paidBy(DateTime(2026, 10, 5)), 0);
      expect(s.paidBy(DateTime(2027, 1, 3)), 3);
      expect(s.nextAfter(DateTime(2027, 1, 3)), DateTime(2027, 2, 3));
      expect(s.lastDueAt, DateTime(2027, 10, 3));
      expect(s.leftMinor(DateTime(2027, 1, 3)), 9 * 333000);
      expect(
        EmiSchedule.firstFrom(DateTime(2026, 11, 5), 14),
        DateTime(2025, 9, 5),
      );
    });

    test('a spread card purchase counts one instalment a month', () async {
      await ingest.ingest(cardSpend(39960, DateTime(2026, 10, 3, 13)));
      final purchase = (await txns()).single;
      await emis.convertPurchase(
        transactionId: purchase.id,
        count: 12,
        amountMinor: 333000,
        firstDueAt: DateTime(2026, 11, 3),
      );
      final rows = await txns();
      expect(rows.single.emi?.isPurchase, isTrue);
      expect(rows.single.countsInTotals, isFalse);
      expect(summarize(oct.from, rows).spentMinor, 0);

      final nov = DateTime(2026, 11);
      final v = await emis.virtualInstalments([
        nov,
      ], now: DateTime(2026, 11, 20));
      expect(v.single.amountMinor, 333000);
      expect(summarize(nov, v).spentMinor, 333000);
      // Not yet due: nothing counted.
      expect(
        await emis.virtualInstalments([nov], now: DateTime(2026, 11, 1)),
        isEmpty,
      );
    });

    test('unspread: the purchase counts once, instalments do not', () async {
      await ingest.ingest(cardSpend(39960, DateTime(2026, 10, 3, 13)));
      final purchase = (await txns()).single;
      await emis.convertPurchase(
        transactionId: purchase.id,
        count: 12,
        amountMinor: 333000,
        firstDueAt: DateTime(2026, 11, 3),
        spread: false,
      );
      expect(summarize(oct.from, await txns()).spentMinor, 3996000);
      expect(
        await emis.virtualInstalments([
          DateTime(2026, 11),
        ], now: DateTime(2026, 11, 20)),
        isEmpty,
      );
    });

    test('a loan EMI links its monthly debit', () async {
      await ingest.ingest(
        axisOut(500, DateTime(2026, 10, 1, 9), payee: 'GROCER'),
      );
      final savings = (await txns()).single.account!.id;
      await emis.addLoan(
        name: 'Home loan',
        accountId: savings,
        amountMinor: 2486000,
        count: 240,
        paid: 14,
        nextDueAt: DateTime(2026, 11, 5),
      );
      await ingest.ingest(
        axisOut(24860, DateTime(2026, 11, 6, 8), payee: 'HDFC LTD NACH'),
      );
      await emis.refresh(now: DateTime(2026, 11, 7));
      final nov = await txns(TxnFilter.month(DateTime(2026, 11)));
      expect(nov.single.emi?.name, 'Home loan');
      expect(nov.single.emi?.isPurchase, isFalse);
      // A loan EMI is real money out: it counts.
      expect(nov.single.countsInTotals, isTrue);
    });

    test('stop tracking puts the purchase back', () async {
      await ingest.ingest(cardSpend(39960, DateTime(2026, 10, 3, 13)));
      final purchase = (await txns()).single;
      final id = await emis.convertPurchase(
        transactionId: purchase.id,
        count: 12,
        amountMinor: 333000,
        firstDueAt: DateTime(2026, 11, 3),
      );
      await emis.remove(id);
      final rows = await txns();
      expect(rows.single.emi, isNull);
      expect(summarize(oct.from, rows).spentMinor, 3996000);
    });
  });
}
