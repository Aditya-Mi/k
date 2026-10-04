import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/app_database.dart' hide ParserTemplate, SenderRule;
import 'package:k/data/email/email_source.dart';
import 'package:k/data/email/email_sync.dart';
import 'package:k/data/ingest/ingestion_service.dart';
import 'package:k/data/repositories/ledger_models.dart';
import 'package:k/data/repositories/ledger_repository.dart';
import 'package:k/data/repositories/settings_repository.dart';

import 'dedup_test.dart' as d;

class FakeSource implements EmailSource {
  FakeSource(this.inbox);

  final List<FetchedEmail> inbox;
  final calls = <(List<String>, String?, DateTime)>[];
  Object? fail;

  @override
  Future<FetchResult> fetch({
    required List<String> senders,
    String? cursor,
    required DateTime since,
  }) async {
    calls.add((senders, cursor, since));
    if (fail != null) throw fail!;
    final start = int.tryParse(cursor ?? '') ?? 0;
    return FetchResult(inbox.skip(start).toList(), '${inbox.length}');
  }

  @override
  Future<void> verify() async {}
}

FetchedEmail fromIncoming(IncomingMessage m) => FetchedEmail(
  externalId: '<${m.receivedAt.millisecondsSinceEpoch}@axis>',
  sender: m.sender,
  subject: m.subject,
  body: m.body,
  receivedAt: m.receivedAt,
);

void main() {
  late AppDatabase db;
  late IngestionService ingest;
  late EmailSync sync;
  late FakeSource source;
  final oct = TxnFilter.month(DateTime(2026, 10));
  final at = DateTime(2026, 10, 2, 21, 36, 2);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    ingest = IngestionService(db);
    source = FakeSource([fromIncoming(d.email(25, at))]);
    sync = EmailSync(
      db,
      ingest,
      SettingsRepository(db),
      const FlutterSecureStorage(),
      sources: (_, secret) async => secret == null ? null : source,
      verifyImap: (_, _) async {},
    );
  });
  tearDown(() => db.close());

  test('add inbox imports bank mail and merges with SMS', () async {
    await ingest.ingest(d.sms(25, at));
    await sync.addImap(
      email: 'Me@Gmail.com',
      appPassword: 'abcd efgh ijkl mnop',
      since: DateTime(2026, 10),
    );
    final (senders, cursor, since) = source.calls.single;
    expect(senders, containsAll(['axis.bank.in', 'kotak.com']));
    expect(cursor, isNull);
    expect(since, DateTime(2026, 10));

    final rows = await LedgerRepository(db).watchTransactions(oct).first;
    expect(rows.single.sourceCount, 2);

    final acc = (await sync.watch().first).single;
    expect(acc.row.email, 'me@gmail.com');
    expect(acc.row.syncCursor, '1');
    expect(acc.error, isNull);
  });

  test('next sync continues from the cursor; re-fetch is idempotent', () async {
    await sync.addImap(
      email: 'me@gmail.com',
      appPassword: 'x',
      since: DateTime(2026, 10),
    );
    source.inbox.add(
      fromIncoming(d.email(40, at.add(const Duration(hours: 2)))),
    );
    expect(await sync.syncAll(), 1);
    expect(source.calls.last.$2, '1');
    expect(await sync.syncAll(), 0);
    expect(
      await LedgerRepository(db).watchTransactions(oct).first,
      hasLength(2),
    );
  });

  test('a refused login is shown on the inbox and clears on success', () async {
    await sync.addImap(
      email: 'me@gmail.com',
      appPassword: 'x',
      since: DateTime(2026, 10),
    );
    source.fail = const EmailAuthException('Sign-in failed');
    await sync.syncAll();
    expect((await sync.watch().first).single.error, 'Sign-in failed');
    source.fail = null;
    await sync.syncAll();
    expect((await sync.watch().first).single.error, isNull);
  });

  test('removed inbox stops syncing', () async {
    await sync.addImap(
      email: 'me@gmail.com',
      appPassword: 'x',
      since: DateTime(2026, 10),
    );
    final id = (await sync.watch().first).single.row.id;
    await sync.remove(id);
    expect(await sync.watch().first, isEmpty);
    expect(await sync.syncAll(), 0);
    expect(source.calls, hasLength(1));
  });
}
