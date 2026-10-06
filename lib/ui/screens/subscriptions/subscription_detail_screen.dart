import 'package:flutter/material.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../categories/category_edit_screen.dart';
import '../../../data/db/app_database.dart' show Category;
import '../../../data/db/enums.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../data/subscriptions/subscription_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/note_chip.dart';
import '../../widgets/text_prompt.dart';
import '../../widgets/txn_row.dart';
import '../txn_detail/txn_detail_screen.dart';
import 'subscription_parts.dart';

/// One plan: price, next charge, settings and the charges matched to it
/// (design 04b).
class SubscriptionDetailScreen extends StatelessWidget {
  const SubscriptionDetailScreen({super.key, required this.id});

  final String id;

  SubscriptionService get _service => getIt<SubscriptionService>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<SubscriptionView?>(
        stream: _service.watchOne(id),
        builder: (context, snap) {
          final sub = snap.data;
          if (sub == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _Header(sub: sub, screen: this),
              const SizedBox(height: 24),
              _Fields(sub: sub, screen: this),
              const SizedBox(height: 24),
              _Charges(id: id),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _stop(context, sub),
                  icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
                  label: const Text('Stop tracking'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rename(BuildContext context, SubscriptionView sub) async {
    final name = await promptText(context, title: 'Name', initial: sub.name);
    if (name != null && name.trim().isNotEmpty) {
      await _service.rename(sub.id, name);
    }
  }

  Future<void> _editAmount(BuildContext context, SubscriptionView sub) async {
    final text = await promptText(
      context,
      title: 'Amount',
      initial: (sub.amountMinor / 100).toStringAsFixed(0),
      numeric: true,
    );
    final minor = text == null ? null : parseAmountMinor(text);
    if (minor != null && minor > 0) await _service.setAmount(sub.id, minor);
  }

  Future<void> _editFrequency(
    BuildContext context,
    SubscriptionView sub,
  ) async {
    const options = [
      SubscriptionFrequency.monthly,
      SubscriptionFrequency.quarterly,
      SubscriptionFrequency.halfYearly,
      SubscriptionFrequency.yearly,
    ];
    final picked = await showModalBottomSheet<SubscriptionFrequency>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in options)
              ListTile(
                title: Text(frequencyLabel(f, sub.row.intervalDays)),
                trailing: f == sub.row.frequency
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _service.setFrequency(sub.id, picked);
  }

  Future<void> _editNext(BuildContext context, SubscriptionView sub) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      helpText: 'Next charge',
      initialDate: sub.row.nextExpectedAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (day != null) await _service.setNextCharge(sub.id, day);
  }

  Future<void> _editReminder(BuildContext context, SubscriptionView sub) async {
    final fallback = await _service.defaultReminderDays();
    if (!context.mounted) return;
    final d = await pickReminder(
      context,
      current: sub.reminderDays,
      defaultDays: fallback,
      usingDefault: sub.usesDefaultReminder,
    );
    if (d == null) return;
    await _service.setReminder(sub.id, d < 0 ? null : d);
  }

  Future<void> _editCategory(
    BuildContext context,
    SubscriptionView sub,
    List<Category> categories,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final cat in categories)
                ListTile(
                  leading: Icon(categoryIcon(cat.icon), color: context.k.text2),
                  title: Text(cat.name),
                  trailing: cat.id == sub.row.categoryId
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, cat.id),
                ),
              newCategoryTile(context, (c) => c.id),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await _service.setCategory(sub.id, picked);
  }

  Future<void> _stop(BuildContext context, SubscriptionView sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop tracking ${sub.name}?'),
        content: const Text('No more reminders. Past charges stay.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop tracking'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.stop(sub.id);
    if (context.mounted) Navigator.pop(context);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.sub, required this.screen});

  final SubscriptionView sub;
  final SubscriptionDetailScreen screen;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final next = sub.row.nextExpectedAt;
    final since = sub.chargeDates.isEmpty ? null : sub.chargeDates.first;
    final meta = [
      frequencyLabel(sub.row.frequency, sub.row.intervalDays),
      if (sub.account != null) sub.account!.short,
      if (sub.autoPay) 'AutoPay',
      if (since != null) 'tracking since ${monthShort(since, DateTime.now())}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Seal(name: sub.name, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: () => screen._rename(context, sub),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.name, style: t.headline),
                    const SizedBox(height: 4),
                    Text(meta, style: t.meta),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LargeNoteChip(amountMinor: sub.amountMinor),
            Text(inr(sub.amountMinor), style: t.amountHero),
            if (sub.priceUp) PriceUpBadge(was: sub.previousAmountMinor!),
          ],
        ),
        if (next != null) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: () => screen._editNext(context, sub),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Next charge ${dayShort(next)}',
                          style: t.body.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(dueIn(next, DateTime.now()), style: t.meta),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CycleBar(sub: sub, fullWidth: true),
                ],
              ),
            ),
          ),
        ],
        if (sub.row.unused) ...[
          const SizedBox(height: 12),
          Text('Marked unused', style: t.meta.copyWith(color: c.text3)),
        ],
      ],
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.sub, required this.screen});

  final SubscriptionView sub;
  final SubscriptionDetailScreen screen;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    Widget editable(String v) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            v,
            style: t.body.copyWith(fontWeight: FontWeight.w500),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.edit_outlined, size: 16, color: c.text2),
      ],
    );
    return Column(
      children: [
        FieldRow(
          label: 'Amount',
          onTap: () => screen._editAmount(context, sub),
          value: editable(inr(sub.amountMinor)),
        ),
        FieldRow(
          label: 'Repeats',
          onTap: () => screen._editFrequency(context, sub),
          value: editable(
            frequencyLabel(sub.row.frequency, sub.row.intervalDays),
          ),
        ),
        if (sub.account != null)
          FieldRow(
            label: 'Account',
            value: Text(
              sub.account!.short,
              style: t.body.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        StreamBuilder<List<Category>>(
          stream: getIt<LedgerRepository>().watchCategories(),
          builder: (context, snap) {
            final cats = snap.data ?? const <Category>[];
            final cat = cats.where((x) => x.id == sub.row.categoryId);
            return FieldRow(
              label: 'Category',
              value: CategoryButton(
                category: cat.firstOrNull,
                onTap: () => screen._editCategory(context, sub, cats),
              ),
            );
          },
        ),
        FieldRow(
          label: 'Remind me',
          onTap: () => screen._editReminder(context, sub),
          value: editable(reminderLabel(sub.reminderDays)),
        ),
        InkWell(
          onTap: () =>
              getIt<SubscriptionService>().setUnused(sub.id, !sub.row.unused),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.outline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Not using it',
                        style: t.body.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text('Flags it in the list', style: t.meta),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Switch(
                  value: sub.row.unused,
                  onChanged: (v) =>
                      getIt<SubscriptionService>().setUnused(sub.id, v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Charges extends StatelessWidget {
  const _Charges({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return StreamBuilder<List<TxnView>>(
      stream: getIt<LedgerRepository>().watchCharges(id),
      builder: (context, snap) {
        final rows = snap.data ?? const <TxnView>[];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Charges', style: t.title),
            const SizedBox(height: 2),
            Text(
              '${rows.length} ${rows.length == 1 ? 'payment' : 'payments'} '
              'matched',
              style: t.meta,
            ),
            const SizedBox(height: 4),
            for (final r in rows)
              TxnRow(
                txn: r,
                title: dayShort(r.occurredAt),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TxnDetailScreen(txnId: r.id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
