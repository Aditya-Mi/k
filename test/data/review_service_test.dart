import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/review/field_marks.dart';
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
    review = ReviewService(db, ingest, ledger);
  });
  tearDown(() => db.close());

  test('ref selection trims to the id inside a NEFT string', () {
    const text = 'Info: NEFT/IN827459235/FOOT.view';
    final start = text.indexOf('NEFT/');
    final r = trimToField(text, MarkField.ref, start, text.length)!;
    expect(text.substring(r.$1, r.$2), 'IN827459235');
  });

  test('queue item: reason and prefilled marks', () async {
    await ingest.ingest(
      axis(
        unknownShape('99', '1234', 'NEWMERCHANT', '88776655'),
        DateTime(2026, 10, 3, 13),
      ),
    );
    final item = (await review.watchQueue().first).single;
    expect(item.reason, 'No format matched');
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
