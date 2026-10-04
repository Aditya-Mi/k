import 'package:enough_mail/enough_mail.dart';

import 'email_source.dart';

/// IMAP over TLS with an app password (Gmail: imap.gmail.com:993). Searches
/// All Mail when the server has it (bank alerts are often auto-archived),
/// else INBOX. Cursor = "uidValidity:lastUid".
class ImapSource implements EmailSource {
  ImapSource({
    required this.email,
    required this.password,
    this.host = 'imap.gmail.com',
    this.port = 993,
  });

  final String email;
  final String password;
  final String host;
  final int port;

  static const _batch = 50;

  Future<ImapClient> _open() async {
    final client = ImapClient(
      defaultResponseTimeout: const Duration(seconds: 30),
    );
    await client.connectToServer(host, port);
    try {
      await client.login(email, password);
    } on ImapException catch (e) {
      await client.disconnect();
      throw EmailAuthException(
        'Sign-in failed: ${e.message ?? 'check the app password'}',
      );
    }
    return client;
  }

  @override
  Future<void> verify() async {
    final client = await _open();
    await client.logout();
  }

  @override
  Future<FetchResult> fetch({
    required List<String> senders,
    String? cursor,
    required DateTime since,
  }) async {
    if (senders.isEmpty) return FetchResult(const [], cursor);
    final client = await _open();
    try {
      final boxes = await client.listMailboxes(recursive: true);
      final all = boxes.where((b) => b.hasFlag(MailboxFlag.all)).firstOrNull;
      final box = all != null
          ? await client.selectMailbox(all)
          : await client.selectInbox();

      final (validity, lastUid) = _parse(cursor);
      final sameBox = validity != null && validity == box.uidValidity;
      final criteria = StringBuffer();
      if (sameBox) {
        criteria.write('UID ${lastUid + 1}:* ');
      } else {
        criteria.write('SINCE ${_imapDate(since)} ');
      }
      criteria.write(_fromAny(senders));
      final search = await client.uidSearchMessages(
        searchCriteria: criteria.toString(),
      );
      final uids = [
        ...?search.matchingSequence?.toList(),
      ].where((u) => !sameBox || u > lastUid).toList()..sort();

      final emails = <FetchedEmail>[];
      var maxUid = sameBox ? lastUid : 0;
      for (var i = 0; i < uids.length; i += _batch) {
        final page = uids.sublist(i, (i + _batch).clamp(0, uids.length));
        final fetched = await client.uidFetchMessages(
          MessageSequence.fromIds(page, isUid: true),
          '(UID INTERNALDATE BODY.PEEK[])',
        );
        for (final m in fetched.messages) {
          final e = _toEmail(m);
          if (e != null) emails.add(e);
          if ((m.uid ?? 0) > maxUid) maxUid = m.uid!;
        }
      }
      final next = box.uidValidity == null
          ? cursor
          : '${box.uidValidity}:${uids.isEmpty && !sameBox ? (box.uidNext ?? 1) - 1 : maxUid}';
      return FetchResult(emails, next);
    } finally {
      await client.logout().catchError((_) {});
    }
  }

  FetchedEmail? _toEmail(MimeMessage m) {
    final body = m.decodeTextPlainPart() ?? m.decodeTextHtmlPart();
    if (body == null) return null;
    final from = m.from?.firstOrNull;
    final sender = from == null
        ? (m.fromEmail ?? '')
        : (from.hasPersonalName
              ? '${from.personalName} <${from.email}>'
              : from.email);
    final at = m.decodeDate()?.toLocal() ?? DateTime.now();
    return FetchedEmail(
      externalId:
          m.getHeaderValue('message-id')?.trim() ?? 'uid:${m.uid ?? at}',
      sender: sender,
      subject: m.decodeSubject(),
      body: body,
      receivedAt: at,
    );
  }

  static (int?, int) _parse(String? cursor) {
    final parts = cursor?.split(':');
    if (parts == null || parts.length != 2) return (null, 0);
    return (int.tryParse(parts[0]), int.tryParse(parts[1]) ?? 0);
  }

  /// OR FROM a OR FROM b FROM c (IMAP prefix OR is binary).
  static String _fromAny(List<String> senders) {
    String q(String s) => 'FROM "${s.replaceAll('"', '')}"';
    var out = q(senders.last);
    for (final s in senders.reversed.skip(1)) {
      out = 'OR ${q(s)} $out';
    }
    return out;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _imapDate(DateTime d) =>
      '${d.day}-${_months[d.month - 1]}-${d.year}';
}
