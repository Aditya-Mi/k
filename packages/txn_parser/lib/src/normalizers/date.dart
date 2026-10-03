const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

// 2026:10:05 / 2026-10-05 (BOB uses colons)
final _ymd = RegExp(r'(\d{4})[:\-/](\d{1,2})[:\-/](\d{1,2})(?!\d)');

// 05-10-26 / 05/10/2026 / 04-Oct-2026 / 4 Oct 2026
final _dmy = RegExp(
  r'(\d{1,2})[\-/ ](\d{1,2}|[A-Za-z]{3,9})[\-/ ,]+(\d{4}|\d{2})(?!\d)',
);

final _time = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([AaPp][Mm]))?');

class BankDate {
  const BankDate(this.value, {required this.hasTime});

  /// Local time — bank alerts are in IST and so is the phone.
  final DateTime value;
  final bool hasTime;
}

/// Tolerant parser for the date formats Indian banks use (day-first).
BankDate? parseBankDate(String raw) {
  int? y, mo, d;
  var rest = raw;

  final ymd = _ymd.firstMatch(raw);
  if (ymd != null) {
    y = int.parse(ymd.group(1)!);
    mo = int.parse(ymd.group(2)!);
    d = int.parse(ymd.group(3)!);
    rest = raw.substring(ymd.end);
  } else {
    final dmy = _dmy.firstMatch(raw);
    if (dmy == null) return null;
    d = int.parse(dmy.group(1)!);
    final m = dmy.group(2)!;
    mo = int.tryParse(m) ?? _months[m.substring(0, 3).toLowerCase()];
    y = int.parse(dmy.group(3)!);
    if (y < 100) y += 2000;
    rest = raw.substring(dmy.end);
  }
  if (mo == null || mo < 1 || mo > 12 || d < 1 || d > 31) return null;

  var h = 0, min = 0, sec = 0;
  final t = _time.firstMatch(rest);
  if (t != null) {
    h = int.parse(t.group(1)!);
    min = int.parse(t.group(2)!);
    sec = int.parse(t.group(3) ?? '0');
    final ampm = t.group(4)?.toLowerCase();
    if (ampm == 'pm' && h < 12) h += 12;
    if (ampm == 'am' && h == 12) h = 0;
    if (h > 23 || min > 59 || sec > 59) return null;
  }

  final value = DateTime(y, mo, d, h, min, sec);
  // Reject rollovers like 31-02 → 03-03.
  if (value.month != mo || value.day != d) return null;
  return BankDate(value, hasTime: t != null);
}

/// Best transaction time: the parsed date, borrowing [receivedAt]'s clock
/// when the alert carries no time and it arrived the same day.
DateTime resolveOccurredAt(BankDate? parsed, DateTime receivedAt) {
  if (parsed == null) return receivedAt;
  if (parsed.hasTime) return parsed.value;
  final p = parsed.value;
  final sameDay = p.year == receivedAt.year &&
      p.month == receivedAt.month &&
      p.day == receivedAt.day;
  return sameDay ? receivedAt : p;
}
