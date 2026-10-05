import 'package:txn_parser/txn_parser.dart';

/// Fields the owner can mark in a message. Direction is a toggle, not a mark
/// that must exist, but marking the word lets one format serve both ways.
enum MarkField {
  account(Fields.last4, 'ACCOUNT'),
  direction(Fields.direction, 'DIRECTION'),
  amount(Fields.amount, 'AMOUNT'),
  payee(Fields.payee, 'PAYEE'),
  ref(Fields.ref, 'REF'),
  date(Fields.date, 'DATE'),
  balance(Fields.balance, 'BALANCE'),

  /// AutoPay alerts only: the day the charge will be taken.
  dueDate(Fields.dueDate, 'DUE ON');

  const MarkField(this.group, this.caption);

  /// txn_parser named group.
  final String group;
  final String caption;
}

/// A marked character range in the normalized message text.
class FieldMark {
  const FieldMark(this.field, this.start, this.end);

  final MarkField field;
  final int start;
  final int end;

  String valueIn(String text) => text.substring(start, end);

  bool overlaps(int s, int e) => s < end && e > start;
}

final _number = RegExp(r'\d[\d,]*(?:\.\d{1,2})?');
final _dateShapes = RegExp(
  r'\b\d{1,4}[-/:]\d{1,2}[-/:]\d{2,4}\b'
  r'|\b\d{1,2}[-\s][A-Za-z]{3}[-\s]\d{2,4}\b',
);
final _directionWords = RegExp(
  r'\b(debited|credited|spent|sent|paid|received|withdrawn|deposited)\b',
  caseSensitive: false,
);

/// Narrows a selection to what the field can hold: "XX1234" → "1234",
/// "Rs.99.00" → "99.00", "03-10-26." → "03-10-26", "SWIGGY," → "SWIGGY",
/// "NEFT/IN26000000000001/ACME" → "IN26000000000001".
(int, int)? trimToField(String text, MarkField field, int start, int end) {
  final s = text.substring(start, end);
  RegExpMatch? m;
  switch (field) {
    case MarkField.account:
      final all = RegExp(r'\d{4}').allMatches(s).toList();
      if (all.isEmpty) return null;
      final last = all.last;
      // Last four digits of the run ("XXXXXX3333" → "3333").
      final runEnd = last.end;
      return (start + runEnd - 4, start + runEnd);
    case MarkField.amount:
    case MarkField.balance:
      m = _number.firstMatch(s);
    case MarkField.ref:
      // Longest run with a digit: "NEFT/IN26000000000001/ACME" → "IN26000000000001".
      final runs = RegExp('[A-Za-z0-9]{4,}').allMatches(s).toList();
      final withDigit = runs.where((r) => r[0]!.contains(RegExp(r'\d')));
      final pool = withDigit.isEmpty ? runs : withDigit;
      m = pool.isEmpty
          ? null
          : pool.reduce((a, b) => b[0]!.length > a[0]!.length ? b : a);
    case MarkField.date:
    case MarkField.dueDate:
      m = _dateShapes.firstMatch(s);
      if (m == null) {
        final t = _trimPunct(s);
        return t == null ? null : (start + t.$1, start + t.$2);
      }
    case MarkField.direction:
      m = RegExp('[A-Za-z]+').firstMatch(s);
    case MarkField.payee:
      final t = _trimPunct(s);
      return t == null ? null : (start + t.$1, start + t.$2);
  }
  if (m == null) return null;
  return (start + m.start, start + m.end);
}

(int, int)? _trimPunct(String s) {
  final m = RegExp(r'^[\s.,;:()\-]*(.*?)[\s.,;:()\-]*$').firstMatch(s);
  final inner = m?.group(1) ?? '';
  if (inner.isEmpty) return null;
  final i = s.indexOf(inner);
  return (i, i + inner.length);
}

/// Places marks for what the parser guessed, by finding each value in the
/// text. Anything it cannot place is left for the owner to mark.
List<FieldMark> prefillMarks(String text, ParsedFields f) {
  final marks = <FieldMark>[];
  bool free(int s, int e) => !marks.any((m) => m.overlaps(s, e));
  void add(MarkField field, int s, int e) {
    if (free(s, e)) marks.add(FieldMark(field, s, e));
  }

  void addNumber(MarkField field, int? minor) {
    if (minor == null) return;
    final hits = _number
        .allMatches(text)
        .where((m) => parseAmountMinor(m.group(0)!) == minor)
        .toList();
    // Prefer the one right after a currency word.
    hits.sort((a, b) => _currencyBefore(text, b) - _currencyBefore(text, a));
    for (final h in hits) {
      if (free(h.start, h.end)) return add(field, h.start, h.end);
    }
  }

  addNumber(MarkField.amount, f.amountMinor);
  addNumber(MarkField.balance, f.balanceMinor);

  if (f.last4 != null) {
    for (final m in RegExp(RegExp.escape(f.last4!)).allMatches(text)) {
      if (free(m.start, m.end)) {
        add(MarkField.account, m.start, m.end);
        break;
      }
    }
  }
  final dir = _directionWords.firstMatch(text);
  if (dir != null) add(MarkField.direction, dir.start, dir.end);

  for (final (field, value) in [
    (MarkField.payee, f.payee),
    (MarkField.ref, f.ref),
  ]) {
    if (value == null || value.isEmpty) continue;
    final i = text.toLowerCase().indexOf(value.toLowerCase());
    if (i >= 0) add(field, i, i + value.length);
  }
  for (final m in _dateShapes.allMatches(text)) {
    if (parseBankDate(m.group(0)!) != null && free(m.start, m.end)) {
      add(MarkField.date, m.start, m.end);
      break;
    }
  }
  return marks..sort((a, b) => a.start.compareTo(b.start));
}

int _currencyBefore(String text, RegExpMatch m) {
  final before = text.substring(0, m.start).toLowerCase().trimRight();
  return before.endsWith('rs') ||
          before.endsWith('rs.') ||
          before.endsWith('inr') ||
          before.endsWith('₹')
      ? 1
      : 0;
}
