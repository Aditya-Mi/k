import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/db/seed/seed_data.dart';
import 'package:k/data/ingest/category_resolver.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/bank_repository.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/review/field_marks.dart';
import 'package:k/data/review/learned_formats.dart';
import 'package:k/data/review/review_service.dart';
import 'package:txn_parser/txn_parser.dart';

IncomingMessage axis(String body, DateTime at) => IncomingMessage(
  channel: Channel.sms,
  sender: 'AX-AXISBK-S',
  body: body,
  receivedAt: at,
);

String unknownShape(String amount, String last4, String payee, String ref) =>
    'Your a/c XX$last4 has been debited for Rs $amount towards $payee ref no '
    '$ref. Axis Bank';

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late LedgerRepository ledger;
  late ReviewService review;
  final oct = TxnFilter.month(DateTime(2026, 10));

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ingest = IngestionService(db);
    ledger = LedgerRepository(db, onRulesChanged: ingest.invalidate);
    review = ReviewService(
      db,
      ingest,
      ledger,
      BankRepository(db, onRulesChanged: ingest.invalidate),
    );
  });
  tearDown(() => db.close());

  test('ref selection trims to the id inside a NEFT string', () {
    const text = 'Info: NEFT/IN26000000000001/ACME.view';
    final start = text.indexOf('NEFT/');
    final r = trimToField(text, MarkField.ref, start, text.length)!;
    expect(text.substring(r.$1, r.$2), 'IN26000000000001');
  });

  test('account selection keeps the last 4 of a longer number', () {
    for (final (word, want) in [
      ('XX100640', '0640'),
      ('XXXXXX3333', '3333'),
      ('X2222.', '2222'),
    ]) {
      final r = trimToField(word, MarkField.account, 0, word.length)!;
      expect(word.substring(r.$1, r.$2), want, reason: word);
    }
  });

  test('queue item: reason and prefilled marks', () async {
    await ingest.ingest(
      axis(
        unknownShape('99', '1234', 'NEWMERCHANT', '88776655'),
        DateTime(2026, 10, 3, 13),
      ),
    );
    final item = (await review.watchQueue().first).single;
    expect(item.reason, "k couldn't read this message");
    final marks = prefillMarks(item.text, item.guess.fields);
    String? v(MarkField f) =>
        marks.where((m) => m.field == f).firstOrNull?.valueIn(item.text);
    expect(v(MarkField.amount), '99');
    expect(v(MarkField.account), '1234');
    expect(v(MarkField.direction), 'debited');
    expect(v(MarkField.ref), '88776655');
  });

  test(
    'save & learn logs it, learns the format and clears look-alikes',
    () async {
      await ingest.ingest(
        axis(
          unknownShape('99', '1234', 'NEWMERCHANT', '88776655'),
          DateTime(2026, 10, 3, 13),
        ),
      );
      await ingest.ingest(
        axis(
          unknownShape('450.50', '1234', 'CORNER STORE', '11223344'),
          DateTime(2026, 10, 4, 9),
        ),
      );
      final queue = await review.watchQueue().first;
      expect(queue, hasLength(2));
      final item = queue.firstWhere((i) => i.text.contains('NEWMERCHANT'));
      final marks = prefillMarks(item.text, item.guess.fields);
      final payeeAt = item.text.indexOf('NEWMERCHANT');
      final result = await review.save(
        item,
        ReviewDraft(
          marks: [
            ...marks.where((m) => m.field != MarkField.payee),
            FieldMark(MarkField.payee, payeeAt, payeeAt + 'NEWMERCHANT'.length),
          ],
          direction: Direction.debit,
          categoryId: 'cat_shopping',
        ),
      );
      expect(result.learnError, isNull);
      expect(result.learned, isTrue);
      expect(result.cleared, 1);
      expect(await review.watchQueue().first, isEmpty);

      final rows = await ledger.watchTransactions(oct).first;
      expect(rows, hasLength(2));
      final first = rows.firstWhere((r) => r.amountMinor == 9900);
      expect(first.payee, 'Newmerchant');
      expect(first.category?.id, 'cat_shopping');
      expect(first.account?.last4, '1234');
      final second = rows.firstWhere((r) => r.amountMinor == 45050);
      expect(second.payee, 'Corner Store');

      // A brand-new message of that shape now parses on arrival.
      expect(
        await ingest.ingest(
          axis(
            unknownShape('12', '1234', 'NEWMERCHANT', '99887766'),
            DateTime(2026, 10, 5, 8),
          ),
        ),
        IngestOutcome.transaction,
      );
      final newest = (await ledger.watchTransactions(oct).first).first;
      // Merchant rule taught by the category pick.
      expect(newest.category?.id, 'cat_shopping');
      expect(await db.parserTemplates.count().getSingle(), 1);
    },
  );

  test('dragged selection is kept; account and card need 4 digits', () {
    const text = 'A/c no. XX100640 card XX2432';
    final at = text.indexOf('100640');
    expect(exactField(text, MarkField.account, at + 2, at + 6), (
      at + 2,
      at + 6,
    ));
    expect(exactField(text, MarkField.account, at, at + 6), isNull);
    final card = text.indexOf('2432');
    expect(exactField(text, MarkField.card, card, card + 4), (card, card + 4));
  });

  test('a marked card joins the account; not part of the format', () async {
    await ingest.ingest(
      axis(
        unknownShape('99', '1234', 'NEWMERCHANT', '88772432'),
        DateTime(2026, 10, 3, 13),
      ),
    );
    final item = (await review.watchQueue().first).single;
    final refAt = item.text.indexOf('88772432');
    final card = trimToField(item.text, MarkField.card, refAt, refAt + 8)!;
    final result = await review.save(
      item,
      ReviewDraft(
        marks: [
          ...prefillMarks(
            item.text,
            item.guess.fields,
          ).where((m) => m.field != MarkField.ref),
          FieldMark(MarkField.card, card.$1, card.$2),
        ],
        direction: Direction.debit,
      ),
    );
    expect(result.learned, isTrue);
    final account = (await ledger.watchAccounts().first).firstWhere(
      (a) => a.last4 == '1234',
    );
    expect(account.includes, ['card ··2432']);
  });

  test('editing a learned format replaces it and logs nothing', () async {
    await ingest.ingest(
      axis(
        unknownShape('99', '1234', 'NEWMERCHANT', '88776655'),
        DateTime(2026, 10, 3, 13),
      ),
    );
    final item = (await review.watchQueue().first).single;
    await review.save(
      item,
      ReviewDraft(
        marks: prefillMarks(item.text, item.guess.fields),
        direction: Direction.debit,
      ),
    );
    final old = await db.select(db.parserTemplates).getSingle();
    final sample = (await review.itemById(item.raw.id))!;
    final payeeAt = sample.text.indexOf('NEWMERCHANT');
    final result = await review.relearn(
      old.id,
      sample,
      ReviewDraft(
        marks: [
          ...prefillMarks(
            sample.text,
            sample.guess.fields,
          ).where((m) => m.field != MarkField.payee),
          FieldMark(MarkField.payee, payeeAt, payeeAt + 'NEWMERCHANT'.length),
        ],
        direction: Direction.debit,
      ),
    );
    expect(result.learned, isTrue);
    final live = await (db.select(
      db.parserTemplates,
    )..where((t) => t.deletedAt.isNull())).get();
    expect(live, hasLength(1));
    expect(live.single.id, isNot(old.id));
    expect(await ledger.watchTransactions(oct).first, hasLength(1));
  });

  test(
    'filed as an ATM withdrawal: cash in hand, and learned as ATM',
    () async {
      await ingest.ingest(
        axis(
          unknownShape('10000', '1234', 'AXIS BANK L', '88776655'),
          DateTime(2026, 10, 7, 19),
        ),
      );
      final item = (await review.watchQueue().first).single;
      await review.save(
        item,
        ReviewDraft(
          marks: prefillMarks(item.text, item.guess.fields),
          direction: Direction.debit,
          categoryId: atmCategoryId,
        ),
      );
      final row = (await ledger.watchTransactions(oct).first).single;
      expect(row.txnType, TxnType.atm);
      final cash = (await ledger.watchBalances().first)[cashAccountId]!;
      expect(cash.amountMinor, 1000000);

      await ingest.ingest(
        axis(
          unknownShape('500', '1234', 'AXIS BANK L', '11223344'),
          DateTime(2026, 10, 8, 9),
        ),
      );
      final next = (await ledger.watchTransactions(oct).first).firstWhere(
        (r) => r.amountMinor == 50000,
      );
      expect(next.txnType, TxnType.atm);
      expect(next.category?.id, atmCategoryId);
    },
  );

  test('learned formats: list, pause, forget', () async {
    final formats = LearnedFormats(db, ingest);
    await ingest.ingest(
      axis(
        unknownShape('99', '1234', 'NEWMERCHANT', '88776655'),
        DateTime(2026, 10, 3, 13),
      ),
    );
    final item = (await review.watchQueue().first).single;
    await review.save(
      item,
      ReviewDraft(
        marks: prefillMarks(item.text, item.guess.fields),
        direction: Direction.debit,
      ),
    );

    final listed = (await formats.watch().first).single;
    expect(listed.uses, 1);
    expect(listed.bankName, isNotEmpty);
    expect(
      listed.marks
          .firstWhere((m) => m.field == MarkField.amount)
          .valueIn(listed.sampleText!),
      '99',
    );

    Future<IngestOutcome> next(String ref, int day) => ingest.ingest(
      axis(
        unknownShape('12', '1234', 'NEWMERCHANT', ref),
        DateTime(2026, 10, day, 8),
      ),
    );
    await formats.setEnabled(listed.row.id, false);
    expect(await next('10000001', 4), IngestOutcome.needsReview);
    await formats.setEnabled(listed.row.id, true);
    expect(await next('10000002', 5), IngestOutcome.transaction);
    expect((await formats.watch().first).single.uses, 2);

    await formats.forget(listed.row.id);
    expect(await formats.watch().first, isEmpty);
    expect(await next('10000003', 6), IngestOutcome.needsReview);
    // Payments it logged stay.
    expect(await ledger.watchTransactions(oct).first, hasLength(2));
  });

  test('save without the amount marked still logs, but cannot learn', () async {
    await ingest.ingest(
      axis(
        unknownShape('99', '1234', 'X SHOP', '88776655'),
        DateTime(2026, 10, 3, 13),
      ),
    );
    final item = (await review.watchQueue().first).single;
    final result = await review.save(
      item,
      const ReviewDraft(
        marks: [],
        direction: Direction.debit,
        amountMinor: 9900,
      ),
    );
    expect(result.learned, isFalse);
    expect(result.learnError, contains('amount'));
    expect(await ledger.watchTransactions(oct).first, hasLength(1));
  });

  test('not a transaction leaves the queue', () async {
    await ingest.ingest(
      axis(
        unknownShape('99', '1234', 'X SHOP', '88776655'),
        DateTime(2026, 10, 3, 13),
      ),
    );
    final item = (await review.watchQueue().first).single;
    await review.notATransaction(item);
    expect(await review.watchQueue().first, isEmpty);
    expect(await ledger.watchReviewCount().first, 0);
  });

  test('category for all of a merchant re-files and teaches', () async {
    final body =
        'INR 250.00 debited\nA/c no. XX1234\n05-10-26, 14:32:10\n'
        'UPI/P2M/298833881599/CHAI POINT\n'
        'Not you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank';
    await ingest.ingest(axis(body, DateTime(2026, 10, 5, 14, 33)));
    await ingest.ingest(
      axis(
        body.replaceFirst('250.00', '80.00').replaceFirst('14:32', '16:00'),
        DateTime(2026, 10, 5, 16, 1),
      ),
    );
    var rows = await ledger.watchTransactions(oct).first;
    expect(rows.every((r) => r.category?.id == 'cat_uncategorized'), isTrue);

    await ledger.setCategory(rows.first.id, 'cat_food', applyToMerchant: true);
    rows = await ledger.watchTransactions(oct).first;
    expect(rows.every((r) => r.category?.id == 'cat_food'), isTrue);

    await ingest.ingest(
      axis(
        body.replaceFirst('250.00', '60.00').replaceFirst('14:32', '18:00'),
        DateTime(2026, 10, 5, 18, 1),
      ),
    );
    rows = await ledger.watchTransactions(oct).first;
    expect(rows, hasLength(3));
    expect(rows.every((r) => r.category?.id == 'cat_food'), isTrue);
  });
}
