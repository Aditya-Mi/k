import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/db/enums.dart';
import '../../../data/subscriptions/recurrence.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/rosette.dart';

/// Per-name seal in text-2 (DESIGN.md "Subscription seals").
class Seal extends StatelessWidget {
  const Seal({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Rosette(
    size: size,
    color: context.k.text2,
    spec: RosetteSpec.seal(name),
    strokeWidth: size > 48 ? 0.7 : 0.6,
  );
}

String frequencyLabel(SubscriptionFrequency f, int days) => switch (f) {
  SubscriptionFrequency.monthly => 'Monthly',
  SubscriptionFrequency.quarterly => 'Every 3 months',
  SubscriptionFrequency.halfYearly => 'Every 6 months',
  SubscriptionFrequency.yearly => 'Yearly',
  SubscriptionFrequency.custom => 'Every $days days',
};

int daysUntil(DateTime when, DateTime now) => DateTime(
  when.year,
  when.month,
  when.day,
).difference(DateTime(now.year, now.month, now.day)).inDays;

/// "in 3 days", "tomorrow", "today", "2 days late".
String dueIn(DateTime when, DateTime now) {
  final d = daysUntil(when, now);
  if (d == 0) return 'today';
  if (d == 1) return 'tomorrow';
  if (d < 0) return '${-d} ${d == -1 ? 'day' : 'days'} late';
  return 'in $d days';
}

/// Track length is the billing cycle (square-root scaled so a monthly plan
/// still reads; a yearly plan fills the row); the fill is the time left.
class CycleBar extends StatelessWidget {
  const CycleBar({super.key, required this.sub, this.fullWidth = false});

  final SubscriptionView sub;

  /// Detail screen: the track is always the full width.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final days = cycleDays(sub.row.frequency, custom: sub.row.intervalDays);
    final next = sub.row.nextExpectedAt;
    final left = next == null
        ? 0.0
        : (next.difference(DateTime.now()).inHours / 24 / days).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) {
        final track = fullWidth
            ? box.maxWidth
            : box.maxWidth * math.sqrt(math.min(days, 365) / 365);
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: track,
            height: 4,
            decoration: BoxDecoration(
              color: c.surface3,
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: left,
              child: Container(
                decoration: BoxDecoration(
                  color: c.text,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Alert badge: "↑ Price up, was ₹149".
class PriceUpBadge extends StatelessWidget {
  const PriceUpBadge({super.key, required this.was});

  final int was;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
      decoration: BoxDecoration(
        color: c.alertBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward_rounded, size: 12, color: c.alert),
          const SizedBox(width: 2),
          Text(
            'Price up, was ${inr(was)}',
            style: context.kt.label.copyWith(
              fontWeight: FontWeight.w600,
              color: c.alert,
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined text-3 tag: "Marked unused".
class UnusedTag extends StatelessWidget {
  const UnusedTag({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c.text2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Marked unused',
        style: context.kt.label.copyWith(color: c.text2),
      ),
    );
  }
}

String reminderLabel(int days) => switch (days) {
  0 => 'Off',
  1 => '1 day before',
  _ => '$days days before',
};

/// Picks reminder days. With [defaultDays] the first option is "same as
/// the others" (returned as -1). Returns null when dismissed.
Future<int?> pickReminder(
  BuildContext context, {
  required int current,
  int? defaultDays,
  bool usingDefault = false,
}) => showModalBottomSheet<int>(
  context: context,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Remind me', style: context.kt.title),
          ),
        ),
        if (defaultDays != null)
          ListTile(
            title: Text('Same as others (${reminderLabel(defaultDays)})'),
            trailing: usingDefault ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(context, -1),
          ),
        for (final d in const [1, 2, 3, 5, 7, 0])
          ListTile(
            title: Text(reminderLabel(d)),
            trailing: !usingDefault && d == current
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, d),
          ),
      ],
    ),
  ),
);
