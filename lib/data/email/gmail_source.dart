import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:http/http.dart' as http;

import 'email_source.dart';
import 'mime_email.dart';

/// Gmail REST API with a read-only OAuth token. Searches all mail except
/// spam/trash (bank alerts are often auto-archived). Cursor = "ms:<newest
/// internalDate>"; each fetch looks back an hour before it so late-indexed
/// mail isn't missed — repeats are dropped by ingestion's content hash.
class GmailSource implements EmailSource {
  GmailSource({
    required this.accessToken,
    required this.dropToken,
    http.Client? client,
  }) : _http = client ?? http.Client();

  /// Current token, or null when sign-in is needed.
  final Future<String?> Function() accessToken;

  /// Called with a token the API refused, before asking for a fresh one.
  final Future<void> Function(String token) dropToken;

  final http.Client _http;

  static const _api = 'https://gmail.googleapis.com/gmail/v1/users/me';
  static const _overlap = Duration(hours: 1);
  static const _parallel = 8;

  @override
  Future<void> verify() async {
    await _get('/profile');
  }

  @override
  Future<FetchResult> fetch({
    required List<String> senders,
    String? cursor,
    required DateTime since,
  }) async {
    if (senders.isEmpty) return FetchResult(const [], cursor);
    final cursorMs = _parse(cursor);
    final after = cursorMs != null
        ? DateTime.fromMillisecondsSinceEpoch(cursorMs).subtract(_overlap)
        : since;
    final query =
        '${fromAny(senders)} after:${after.millisecondsSinceEpoch ~/ 1000}';

    final ids = <String>[];
    String? page;
    do {
      final list = await _get('/messages', {
        'q': query,
        'maxResults': '100',
        'pageToken': ?page,
      });
      for (final m in (list['messages'] as List? ?? const [])) {
        ids.add((m as Map)['id'] as String);
      }
      page = list['nextPageToken'] as String?;
    } while (page != null);

    final emails = <FetchedEmail>[];
    var newest = cursorMs ?? 0;
    for (var i = 0; i < ids.length; i += _parallel) {
      final batch = ids.sublist(i, (i + _parallel).clamp(0, ids.length));
      final mails = await Future.wait(
        batch.map((id) => _get('/messages/$id', {'format': 'raw'})),
      );
      for (final (j, json) in mails.indexed) {
        final internal = int.tryParse('${json['internalDate']}');
        if (internal != null && internal > newest) newest = internal;
        final raw = json['raw'] as String?;
        if (raw == null) continue;
        final mime = MimeMessage.parseFromData(
          base64Url.decode(base64Url.normalize(raw)),
        );
        final e = emailFromMime(
          mime,
          fallbackId: 'gmail:${batch[j]}',
          fallbackDate: internal == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(internal),
        );
        if (e != null) emails.add(e);
      }
    }
    return FetchResult(emails, newest == 0 ? cursor : 'ms:$newest');
  }

  /// `from:(a OR b)`: addresses or domains from the bank sender rules.
  static String fromAny(List<String> senders) =>
      'from:(${senders.map((s) => s.replaceAll(RegExp(r'[\s"()]'), '')).join(' OR ')})';

  static int? _parse(String? cursor) =>
      cursor != null && cursor.startsWith('ms:')
      ? int.tryParse(cursor.substring(3))
      : null;

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final uri = Uri.parse('$_api$path').replace(queryParameters: query);
    for (var attempt = 0; ; attempt++) {
      final token = await accessToken();
      if (token == null) {
        throw const EmailAuthException('Sign in with Google again');
      }
      final res = await _http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      if (res.statusCode == 401 && attempt == 0) {
        await dropToken(token);
        continue;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const EmailAuthException('Google refused access. Sign in again');
      }
      throw http.ClientException('Gmail ${res.statusCode}', uri);
    }
  }
}
