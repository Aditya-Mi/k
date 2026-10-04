import 'package:enough_mail/enough_mail.dart';

import 'email_source.dart';

/// A parsed mail as k ingests it: plain text when there is one, else HTML.
/// Null when the mail has no readable body.
FetchedEmail? emailFromMime(
  MimeMessage m, {
  required String fallbackId,
  DateTime? fallbackDate,
}) {
  final body = m.decodeTextPlainPart() ?? m.decodeTextHtmlPart();
  if (body == null) return null;
  final from = m.from?.firstOrNull;
  final sender = from == null
      ? (m.fromEmail ?? '')
      : (from.hasPersonalName
            ? '${from.personalName} <${from.email}>'
            : from.email);
  final at = m.decodeDate()?.toLocal() ?? fallbackDate ?? DateTime.now();
  return FetchedEmail(
    externalId: m.getHeaderValue('message-id')?.trim() ?? fallbackId,
    sender: sender,
    subject: m.decodeSubject(),
    body: body,
    receivedAt: at,
  );
}
