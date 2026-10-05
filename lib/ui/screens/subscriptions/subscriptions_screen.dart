import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import '../../../data/emis/emi_service.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/note_chip.dart';
import 'add_subscription_screen.dart';
import 'emi_form_screen.dart';
import 'emi_parts.dart';
import 'subscription_detail_screen.dart';
import 'subscription_parts.dart';

/// Recurring tab (design 13, was 04): totals, suggestions to confirm,
/// tracked plans by next charge, then EMIs.
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return StreamBuilder<(SubscriptionsOverview, List<EmiView>)>(
      stream: Rx.combineLatest2(
        getIt<SubscriptionService>().watch(),
        getIt<EmiService>().watch(),
        (a, b) => (a, b),
      ),
      builder: (context, snap) {
        final o = snap.data?.$1;
        final emis = snap.data?.$2 ?? const <EmiView>[];
        final title = Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: [
              Expanded(child: Text('Recurring', style: t.headline)),
              IconButton(
                tooltip: 'Add',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _add(context),
              ),
            ],
          ),
        );
        if (o == null) {
          return Align(alignment: Alignment.topCenter, child: title);
        }
        if (o.suggestions.isEmpty && o.active.isEmpty && emis.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: EmptyState(
                      title: 'Nothing recurring yet',
                      body:
                          'Repeating charges, AutoPays and EMIs show up here.',
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
                  if (o.active.isNotEmpty || emis.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      [
                        '${inr(o.perMonthMinor + emis.fold(0, (s, e) => s + e.row.amountMinor))} a month',
                        if (o.active.isNotEmpty)
                          '${o.active.length} ${o.active.length == 1 ? 'subscription' : 'subscriptions'}',
                        if (emis.isNotEmpty)
                          '${emis.length} ${emis.length == 1 ? 'EMI' : 'EMIs'}',
                      ].join('  ·  '),
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
                      'Each bar shows time left before the next charge.',
                      style: t.meta.copyWith(
                        color: context.k.text3,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final s in o.active) _SubRow(sub: s),
                  ],
                  if (emis.isNotEmpty) ...[
                    EmiHead(emis: emis),
                    for (final e in emis) EmiRow(emi: e),
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

Future<void> _add(BuildContext context) async {
  final loan = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.autorenew_rounded),
            title: const Text('Subscription'),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Loan EMI'),
            subtitle: const Text('Paid from a bank account each month'),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.credit_card_rounded),
            title: const Text('Card EMI'),
            subtitle: const Text('Open the card payment, then Convert to EMI'),
          ),
        ],
      ),
    ),
  );
  if (loan == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          loan ? const EmiFormScreen.loan() : const AddSubscriptionScreen(),
    ),
  );
}

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
        Expanded(child: Text('Subscriptions', style: t.title)),
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
