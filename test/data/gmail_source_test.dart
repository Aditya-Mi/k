import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:k/data/email/email_source.dart';
import 'package:k/data/email/gmail_source.dart';

String _raw(String id) => base64Url
    .encode(
      utf8.encode(
        'From: Axis Bank <alerts@axis.bank.in>\r\n'
        'Subject: Debit alert\r\n'
        'Message-ID: <$id@axis>\r\n'
        'Date: Mon, 5 Oct 2026 10:00:00 +0530\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        'INR 120.00 debited from A/c no. XX1111\r\n',
      ),
    )
    .replaceAll('=', '');

void main() {
  test('lists bank mail after since, parses raw, cursor = newest', () async {
    final queries = <String>[];
    final source = GmailSource(
      accessToken: () async => 't',
      dropToken: (_) async {},
      client: MockClient((req) async {
        if (req.url.path.endsWith('/messages')) {
          queries.add(req.url.queryParameters['q']!);
          return http.Response(
            jsonEncode({
              'messages': [
                {'id': 'a'},
                {'id': 'b'},
              ],
            }),
            200,
          );
        }
        final id = req.url.pathSegments.last;
        return http.Response(
          jsonEncode({
            'id': id,
            'internalDate': id == 'a' ? '1000000' : '2000000',
            'raw': _raw(id),
          }),
          200,
        );
      }),
    );
    final since = DateTime.fromMillisecondsSinceEpoch(500000 * 1000);
    final r = await source.fetch(
      senders: ['axis.bank.in', 'kotak.com'],
      since: since,
    );
    expect(queries.single, 'from:(axis.bank.in OR kotak.com) after:500000');
    expect(r.emails, hasLength(2));
    expect(r.emails.first.sender, 'Axis Bank <alerts@axis.bank.in>');
    expect(r.emails.first.externalId, '<a@axis>');
    expect(r.emails.first.body, contains('INR 120.00 debited'));
    expect(r.cursor, 'ms:2000000');

    await source.fetch(
      senders: ['axis.bank.in'],
      cursor: r.cursor,
      since: since,
    );
    // Looks back an hour before the newest mail seen.
    expect(queries.last, 'from:(axis.bank.in) after:${2000 - 3600}');
  });

  test('401 drops the token and retries once; no token = auth error', () async {
    final dropped = <String>[];
    var tokens = ['old', 'new'];
    final source = GmailSource(
      accessToken: () async => tokens.removeAt(0),
      dropToken: (t) async => dropped.add(t),
      client: MockClient(
        (req) async => req.headers['Authorization'] == 'Bearer new'
            ? http.Response('{}', 200)
            : http.Response('', 401),
      ),
    );
    await source.verify();
    expect(dropped, ['old']);

    tokens = [];
    final none = GmailSource(
      accessToken: () async => null,
      dropToken: (_) async {},
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(none.verify(), throwsA(isA<EmailAuthException>()));
  });
}
