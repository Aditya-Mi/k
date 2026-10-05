/// Calendar maths for EMIs: instalment n falls due on the same day of month
/// as the first, n months later (clamped to the month's last day).
DateTime addMonths(DateTime at, int months) {
  final lastDay = DateTime(at.year, at.month + months + 1, 0).day;
  return DateTime(
    at.year,
    at.month + months,
    at.day > lastDay ? lastDay : at.day,
    at.hour,
    at.minute,
  );
}

class EmiSchedule {
  const EmiSchedule({
    required this.firstDueAt,
    required this.count,
    required this.amountMinor,
  });

  final DateTime firstDueAt;
  final int count;
  final int amountMinor;

  DateTime dueAt(int n) => addMonths(firstDueAt, n);

  DateTime get lastDueAt => dueAt(count - 1);

  /// Instalments due on or before [now].
  int paidBy(DateTime now) {
    var n = 0;
    while (n < count && !dueAt(n).isAfter(now)) {
      n++;
    }
    return n;
  }

  /// The next instalment after [now], or null when all are due.
  DateTime? nextAfter(DateTime now) {
    final n = paidBy(now);
    return n < count ? dueAt(n) : null;
  }

  int leftMinor(DateTime now) => (count - paidBy(now)) * amountMinor;

  /// Instalments due in the calendar month of [month], up to [now].
  List<(int, DateTime)> dueIn(DateTime month, DateTime now) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return [
      for (var n = 0; n < count; n++)
        if (!dueAt(n).isBefore(start) &&
            dueAt(n).isBefore(end) &&
            !dueAt(n).isAfter(now))
          (n, dueAt(n)),
    ];
  }

  /// [firstDueAt] for a loan already [paid] instalments in, next due [next].
  static DateTime firstFrom(DateTime next, int paid) => addMonths(next, -paid);
}
