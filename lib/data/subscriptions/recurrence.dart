import '../db/enums.dart';

/// One debit, as the detector sees it.
class Charge {
  const Charge(this.id, this.amountMinor, this.at);

  final String id;
  final int amountMinor;
  final DateTime at;
}

/// A run of charges that repeats on a cycle, oldest first.
class Recurrence {
  const Recurrence(this.frequency, this.charges);

  final SubscriptionFrequency frequency;
  final List<Charge> charges;

  Charge get latest => charges.last;
}

/// Gap between charges, in days, that still counts as one cycle.
const _windows = {
  SubscriptionFrequency.monthly: (26, 35),
  SubscriptionFrequency.quarterly: (84, 98),
  SubscriptionFrequency.halfYearly: (174, 190),
  SubscriptionFrequency.yearly: (355, 375),
};

/// Charges needed before a cycle is believed.
const _minRun = {
  SubscriptionFrequency.monthly: 3,
  SubscriptionFrequency.quarterly: 2,
  SubscriptionFrequency.halfYearly: 2,
  SubscriptionFrequency.yearly: 2,
};

/// Nominal cycle length in days.
int cycleDays(SubscriptionFrequency f, {int custom = 30}) => switch (f) {
  SubscriptionFrequency.monthly => 30,
  SubscriptionFrequency.quarterly => 91,
  SubscriptionFrequency.halfYearly => 182,
  SubscriptionFrequency.yearly => 365,
  SubscriptionFrequency.custom => custom,
};

/// The charge after [at]: same day of month for calendar cycles (clamped to
/// the month's last day), else [customDays] later.
DateTime nextCharge(
  DateTime at,
  SubscriptionFrequency f, {
  int customDays = 30,
}) {
  final months = switch (f) {
    SubscriptionFrequency.monthly => 1,
    SubscriptionFrequency.quarterly => 3,
    SubscriptionFrequency.halfYearly => 6,
    SubscriptionFrequency.yearly => 12,
    SubscriptionFrequency.custom => 0,
  };
  if (months == 0) return at.add(Duration(days: customDays));
  final lastDay = DateTime(at.year, at.month + months + 1, 0).day;
  return DateTime(
    at.year,
    at.month + months,
    at.day > lastDay ? lastDay : at.day,
    at.hour,
    at.minute,
  );
}

/// Monthly cost of a plan, for the "a month" total.
int monthlyMinor(int amountMinor, SubscriptionFrequency f, int intervalDays) =>
    switch (f) {
      SubscriptionFrequency.monthly => amountMinor,
      SubscriptionFrequency.quarterly => (amountMinor / 3).round(),
      SubscriptionFrequency.halfYearly => (amountMinor / 6).round(),
      SubscriptionFrequency.yearly => (amountMinor / 12).round(),
      SubscriptionFrequency.custom =>
        (amountMinor * 30.44 / intervalDays).round(),
    };

bool withinTolerance(int a, int b, double tolerance) =>
    (a - b).abs() <= (b * tolerance).round();

/// Finds a repeating run ending at the newest charge. Only charges within
/// [tolerance] of the newest amount count; a similar charge inside a cycle
/// (two in one month) ends the run, so everyday spends at one shop rarely
/// pass. Shortest cycle wins.
Recurrence? detectRecurrence(List<Charge> charges, {double tolerance = 0.10}) {
  if (charges.length < 2) return null;
  final sorted = [...charges]..sort((a, b) => b.at.compareTo(a.at));
  final anchor = sorted.first;
  final similar = [
    for (final c in sorted)
      if (withinTolerance(c.amountMinor, anchor.amountMinor, tolerance)) c,
  ];
  for (final MapEntry(key: f, value: (lo, hi)) in _windows.entries) {
    final run = [anchor];
    var i = 0; // index of the run's oldest charge in [similar]
    while (true) {
      final cur = similar[i];
      int? next;
      for (var j = i + 1; j < similar.length; j++) {
        final gap = cur.at.difference(similar[j].at).inHours / 24;
        if (gap < lo) {
          // Same-cycle repeat: a second one this soon breaks the pattern.
          if (gap >= 1) break;
          continue;
        }
        if (gap <= hi) next = j;
        break;
      }
      if (next == null) break;
      run.add(similar[next]);
      i = next;
    }
    // The loop above stops at a same-cycle repeat; a run that is long
    // enough before that still counts.
    if (run.length >= _minRun[f]!) {
      return Recurrence(f, run.reversed.toList());
    }
  }
  return null;
}
