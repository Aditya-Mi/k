import 'package:flutter_test/flutter_test.dart';
import 'package:k/data/db/enums.dart';
import 'package:k/data/subscriptions/recurrence.dart';

Charge c(String id, int rupees, DateTime at) => Charge(id, rupees * 100, at);

void main() {
  test('three monthly charges make a monthly run', () {
    final r = detectRecurrence([
      c('a', 119, DateTime(2026, 8, 2)),
      c('b', 119, DateTime(2026, 9, 2)),
      c('c', 119, DateTime(2026, 10, 2)),
    ])!;
    expect(r.frequency, SubscriptionFrequency.monthly);
    expect(r.charges.map((x) => x.id), ['a', 'b', 'c']);
  });

  test('two monthly charges are not enough', () {
    expect(
      detectRecurrence([
        c('a', 119, DateTime(2026, 9, 2)),
        c('b', 119, DateTime(2026, 10, 2)),
      ]),
      isNull,
    );
  });

  test('frequent spends at one shop are not a subscription', () {
    expect(
      detectRecurrence([
        for (var d = 1; d <= 90; d += 6) c('$d', 300, DateTime(2026, 7, d)),
      ]),
      isNull,
    );
  });

  test('other amounts at the merchant are ignored', () {
    final r = detectRecurrence([
      c('a', 1499, DateTime(2025, 10, 14)),
      c('x', 640, DateTime(2026, 2, 3)),
      c('b', 1499, DateTime(2026, 10, 14)),
    ])!;
    expect(r.frequency, SubscriptionFrequency.yearly);
    expect(r.charges.map((x) => x.id), ['a', 'b']);
  });

  test('small price drift stays within tolerance', () {
    final r = detectRecurrence([
      c('a', 649, DateTime(2026, 7, 8)),
      c('b', 649, DateTime(2026, 8, 8)),
      c('c', 699, DateTime(2026, 9, 8)),
    ]);
    expect(r?.charges.length, 3);
  });

  test('nextCharge keeps the day, clamped to month end', () {
    expect(
      nextCharge(DateTime(2026, 1, 31), SubscriptionFrequency.monthly),
      DateTime(2026, 2, 28),
    );
    expect(
      nextCharge(DateTime(2026, 3, 14), SubscriptionFrequency.yearly),
      DateTime(2027, 3, 14),
    );
  });

  test('monthly equivalents', () {
    expect(monthlyMinor(149900, SubscriptionFrequency.yearly, 365), 12492);
    expect(monthlyMinor(64900, SubscriptionFrequency.monthly, 30), 64900);
  });
}
