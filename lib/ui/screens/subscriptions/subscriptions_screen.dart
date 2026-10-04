import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/subscriptions/subscription_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/note_chip.dart';
import 'add_subscription_screen.dart';
import 'subscription_detail_screen.dart';
import 'subscription_parts.dart';

/// Totals, suggestions to confirm, then tracked plans by next charge
/// (design 04 / 04c).
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return StreamBuilder<SubscriptionsOverview>(
      stream: getIt<SubscriptionService>().watch(),
      builder: (context, snap) {
        final o = snap.data;
        final title = Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: [
              Expanded(child: Text('Subscriptions', style: t.headline)),
              IconButton(
                tooltip: 'Add subscription',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _add(context),
              ),
            ],
          ),
        );
        if (o == null) {
          return Align(alignment: Alignment.topCenter, child: title);
        }
        if (o.suggestions.isEmpty && o.active.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: EmptyState(
                      title: 'No subscriptions yet',
                      body:
                          'k spots charges that repeat, and AutoPay alerts '
                          'from your bank. After a couple of months of '
                          'payments, suggestions show up here to confirm.',
                      action: OutlinedButton.icon(
                        onPressed: () => _add(context),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Add one yourself'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            title,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (o.active.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${inr(o.perMonthMinor)} a month  ·  '
                      '${inr(o.perYearMinor)} a year  ·  '
                      '${o.active.length} active',
                      style: t.title.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.k.text2,
                      ),
                    ),
                  ],
                  for (final s in o.suggestions) ...[
                    const SizedBox(height: 20),
                    _SuggestionCard(sub: s),
                  ],
                  if (o.active.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _ListHead(reminderDays: o.reminderDays),
                    const SizedBox(height: 12),
                    Text(
                      'Each bar is one billing cycle. The filled part is the '
                      'time left before the next charge.',
                      style: t.meta.copyWith(
                        color: context.k.text3,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final s in o.active) _SubRow(sub: s),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

void _add(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const AddSubscriptionScreen(),
  ),
);

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.sub});

  final SubscriptionView sub;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final dates = sub.chargeDates.map(dayMonth).toList();
    final next = sub.row.nextExpectedAt;
    final what = dates.isEmpty
        ? (next == null
              ? 'AutoPay ${inr(sub.amountMinor)}'
              : 'AutoPay ${inr(sub.amountMinor)} due ${dayShort(next)}')
        : '${inr(sub.amountMinor)} on ${_list(dates)}';
    final account = sub.account == null ? '' : ' · ${sub.account!.short}';
    final service = getIt<SubscriptionService>();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface1,
        border: Border.all(color: c.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Seal(name: sub.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${sub.name} looks like a subscription',
                      style: t.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text('$what$account', style: t.meta.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              NoteChip(amountMinor: sub.amountMinor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => service.dismiss(sub.id),
                child: const Text('Not a subscription'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  await service.track(sub.id);
                  // Reminders need this on Android 13+; asked once, here.
                  await Permission.notification.request();
                  await service.refresh();
                },
                child: const Text('Track it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _list(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

class _ListHead extends StatelessWidget {
  const _ListHead({required this.reminderDays});

  final int reminderDays;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Row(
      children: [
        Expanded(child: Text('Next charges', style: t.title)),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final d = await pickReminder(context, current: reminderDays);
            if (d != null && d >= 0) {
              await getIt<SubscriptionService>().setDefaultReminder(d);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  reminderDays == 0
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  size: 16,
                  color: c.text3,
                ),
                const SizedBox(width: 4),
                Text(
                  reminderDays == 0
                      ? 'Reminders off'
                      : 'Reminds ${reminderLabel(reminderDays)}',
                  style: t.meta.copyWith(color: c.text3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SubRow extends StatelessWidget {
  const _SubRow({required this.sub});

  final SubscriptionView sub;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final now = DateTime.now();
    final next = sub.row.nextExpectedAt;
    final meta = [
      frequencyLabel(sub.row.frequency, sub.row.intervalDays),
      if (next != null) dayShort(next),
      if (next != null && daysUntil(next, now) <= 7) dueIn(next, now),
      if (sub.autoPay) 'AutoPay',
    ].join(' · ');
    return Opacity(
      opacity: sub.row.unused ? 0.6 : 1,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SubscriptionDetailScreen(id: sub.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Seal(name: sub.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              sub.name,
                              style: t.body.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (sub.priceUp)
                              PriceUpBadge(was: sub.previousAmountMinor!),
                            if (sub.row.unused) const UnusedTag(),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(meta, style: t.meta),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  NoteChip(amountMinor: sub.amountMinor),
                  const SizedBox(width: 14),
                  Text(inrRow(sub.amountMinor), style: t.amountRow),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: CycleBar(sub: sub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
