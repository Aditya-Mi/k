import 'enums.dart';
import 'field_mapping.dart';
import 'normalizers/amount.dart';
import 'normalizers/merchant.dart';
import 'parse_result.dart';

// Skips the balance so "AvlBal: Rs.500" is never taken as the amount.
final _amount = RegExp(
  r'(?<!bal\W{0,3}|balance\W{0,3}|lmt\W{0,3}|limit\W{0,3})'
  r'(?:INR|Rs\.?|₹)\s?([\d,]+(?:\.\d{1,2})?)',
  caseSensitive: false,
);
final _balance = RegExp(
  r'(?:avl\.?\s?bal(?:ance)?|available balance|total bal|avl\.?\s?(?:lmt|limit)'
  r'|available limit)\s*[:\-]?\s*(?:INR|Rs\.?|₹)\s?([\d,]+(?:\.\d{1,2})?)',
  caseSensitive: false,
);
// First wording wins. "Dr. from … Cr. to" (BOB) reads as a debit.
final _direction = RegExp(
  r'\b(debited|spent|sent|paid|withdrawn|credited|received|deposited)\b'
  r'|\b(dr|cr)\.\s(?=from|to)'
  r'|\b(autopay|made a (?:\w+ )?payment)\b',
  caseSensitive: false,
);
final _last4 = RegExp(
  r'(?:a/?c|acct|account|card)\s*(?:no\.?)?\s*(?:ending\s*)?[x*.]*(\d{4})\b',
  caseSensitive: false,
);
// UPI/P2M/<ref>/<payee>, NEFT/<utr>/<payee> — Axis style.
final _slashPath = RegExp(
  r'\b(?:UPI|NEFT|IMPS|RTGS)/(?:P2[AM]/)?([A-Za-z0-9]{6,})/([^/]+?)'
  r'(?=\s+(?:Not you|If|Chk|Avl)\b|\.(?:\s|$)|$)',
  caseSensitive: false,
);
final _ref = RegExp(
  r'(?:ref(?:erence)?|utr|rrn|txn id)\s*(?:no\.?|number)?\s*[:\-]?\s*([A-Za-z0-9]{6,})',
  caseSensitive: false,
);
// "to DMRC on 25-09-26", "at WWW AMAZON IN on 01/10", "towards SWIGGY
// through", "Cr. to x@ybl. Ref", "to APPLE will be debited". A payee never
// contains an account word, so "from Kotak Bank AC X1234 to …" can't swallow
// the account; "towards reversal of failed txn" is a reason, not a payee.
final _payee = RegExp(
  r"\b(?:to|at|from|towards)\s+"
  r"(?!reversal|refund)"
  r"([A-Za-z](?:(?!\b(?:a/?c|acct|account|card)\b)[\w .&'@\-]){1,40}?)"
  r'(?:\s+on\s+\d|\s+through\b|\s+will\s+be\b|\.?\s*(?:UPI\s+|IMPS\s+|NEFT\s+|RTGS\s+)?Ref\b)',
  caseSensitive: false,
);

/// Heuristic extraction for unknown formats. Output only pre-fills the
/// review form — never auto-accepted. Prefer null over a wrong value.
ParsedFields guessFields(String text) {
  final amount = _amount.firstMatch(text)?.group(1);
  final balance = _balance.firstMatch(text)?.group(1);
  final dir = _direction.firstMatch(text);
  final path = _slashPath.firstMatch(text);
  final payee = path?.group(2) ?? _payee.firstMatch(text)?.group(1);
  return ParsedFields(
    amountMinor: amount == null ? null : parseAmountMinor(amount),
    direction: dir == null
        ? null
        : directionFromWord(dir.group(1) ?? dir.group(2)) ??
              (dir.group(3) != null ? Direction.debit : null),
    txnType: inferTxnType(text, isMandate: false),
    last4: _last4.firstMatch(text)?.group(1),
    payee: payee == null ? null : cleanPayee(payee),
    ref: path?.group(1) ?? _ref.firstMatch(text)?.group(1),
    balanceMinor: balance == null ? null : parseAmountMinor(balance),
  );
}
