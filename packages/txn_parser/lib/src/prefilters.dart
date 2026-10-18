/// Bank messages that look money-ish but are not completed transactions.
/// Returns the reason, or null if the message should be parsed.
String? nonTransactionReason(String text) {
  if (_otp.hasMatch(text)) return 'otp';
  if (_promo.hasMatch(text)) return 'promotional';
  if (_declined.hasMatch(text) && !_reversal.hasMatch(text)) return 'declined';
  return null;
}

// Delivers an OTP — not a "never share your OTP" footer on a real alert.
final _otp = RegExp(
  r'(\b\d{4,8}\b is (?:the |your )?(?:otp|one[- ]time password))'
  r'|((?:\botp\b|one[- ]time password|verification code)\s*(?:is|:)\s*\d{4,8}\b)',
  caseSensitive: false,
);

final _promo = RegExp(
  r'pre-?approved|apply now|limited period offer|offer valid|exclusive offer'
  r'|get up to',
  caseSensitive: false,
);

final _declined = RegExp(
  r'\b(declined|has failed|was unsuccessful|could not be processed)\b',
  caseSensitive: false,
);

// "credited ... reversal of failed txn" is real money and must be kept.
final _reversal = RegExp(
  r'\b(revers(?:al|ed)|refund(?:ed)?|credited)\b',
  caseSensitive: false,
);

/// Words that say money moved. A bank message no format knows goes to
/// Review only with one of these and an amount (see [ParserEngine.parse]);
/// account-opening, KYC, statement and balance-only messages have neither.
bool movesMoney(String text) => _movement.hasMatch(text);

final _movement = RegExp(
  r'\b(debited|credited|spent|withdrawn|deposited|sent|received|paid'
  r'|transferred|deducted|charged|refund(?:ed)?|revers(?:al|ed)|dr|cr'
  r'|successful(?:ly)?|autopay|purchased?|txn|transaction)\b',
  caseSensitive: false,
);
