/// One bank email as fetched from an inbox.
class FetchedEmail {
  const FetchedEmail({
    required this.externalId,
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.subject,
  });

  /// Message-ID (or provider id): stored for the trail.
  final String externalId;

  /// `Axis Bank <alerts@axis.bank.in>`.
  final String sender;
  final String? subject;

  /// Plain text when the mail has it, else HTML (the parser strips tags).
  final String body;
  final DateTime receivedAt;
}

/// A page of new mail plus where to continue next time.
class FetchResult {
  const FetchResult(this.emails, this.cursor);

  final List<FetchedEmail> emails;
  final String? cursor;
}

/// Login rejected (wrong app password, sign-in revoked): needs the owner.
class EmailAuthException implements Exception {
  const EmailAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads bank mail from one inbox. [senders] are domains or addresses from
/// the bank sender rules; only mail from them is fetched.
abstract interface class EmailSource {
  /// Mail after [cursor], or since [since] when there is no cursor yet.
  Future<FetchResult> fetch({
    required List<String> senders,
    String? cursor,
    required DateTime since,
  });

  /// Checks the credentials work (connect flow).
  Future<void> verify();
}
