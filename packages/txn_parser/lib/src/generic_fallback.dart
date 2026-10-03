import 'field_mapping.dart';
import 'normalizers/amount.dart';
import 'parse_result.dart';

final _amount = RegExp(
  r'(?:INR|Rs\.?|₹)\s?([\d,]+(?:\.\d{1,2})?)',
  caseSensitive: false,
);
final _direction = RegExp(
  r'\b(debited|spent|sent|paid|withdrawn|credited|received|deposited)\b',
  caseSensitive: false,
);
final _last4 = RegExp(
  r'(?:a/?c|acct|account|card)\s*(?:no\.?)?\s*(?:ending\s*)?[x*.]*(\d{4})\b',
  caseSensitive: false,
);
final _ref = RegExp(
  r'(?:ref(?:erence)?|utr|rrn|txn id)\s*(?:no\.?|number)?\s*[:\-]?\s*([A-Za-z0-9]{6,})',
  caseSensitive: false,
);

/// Heuristic extraction for unknown formats. Output only pre-fills the
/// review form — never auto-accepted.
ParsedFields guessFields(String text) {
  final amount = _amount.firstMatch(text)?.group(1);
  return ParsedFields(
    amountMinor: amount == null ? null : parseAmountMinor(amount),
    direction: directionFromWord(_direction.firstMatch(text)?.group(1)),
    last4: _last4.firstMatch(text)?.group(1),
    ref: _ref.firstMatch(text)?.group(1),
  );
}
