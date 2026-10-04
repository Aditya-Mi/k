import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../../data/repositories/ledger_models.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/month_note_panel.dart';
import '../../widgets/txn_row.dart';
import '../accounts/accounts_screen.dart';
import '../settings/settings_screen.dart';
import '../txn_detail/txn_detail_screen.dart';
import 'add_payment_screen.dart';
import 'transactions_cubit.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    required this.smsGranted,
    required this.onOpenReview,
  });

  final ValueListenable<bool?> smsGranted;
  final VoidCallback onOpenReview;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => context.read<TransactionsCubit>().setQuery(q),
    );
  }

  void _closeSearch() {
    _search.clear();
    context.read<TransactionsCubit>().setQuery('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return BlocBuilder<TransactionsCubit, TransactionsState>(
      builder: (context, s) {
        final cubit = context.read<TransactionsCubit>();
        final showUpcoming =
            s.isCurrentMonth && !s.narrowed && s.upcoming.isNotEmpty;
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              titleSpacing: 16,
              automaticallyImplyLeading: false,
              title: _searching
                  ? TextField(
                      controller: _search,
                      autofocus: true,
                      style: t.body,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Search payee, note or ref',
                      ),
                      onChanged: _onSearch,
                    )
                  : Text('k', style: t.wordmark),
              actions: [
                if (!_searching)
                  IconButton(
                    tooltip: 'Add payment',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => const AddPaymentScreen(),
                      ),
                    ),
                  ),
                if (_searching)
                  IconButton(
                    tooltip: 'Close search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _closeSearch,
                  )
                else
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => setState(() => _searching = true),
                  ),
                IconButton(
                  tooltip: 'Accounts',
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountsScreen(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: MonthNotePanel(
                  summary: s.summary,
                  syncedAt: s.isCurrentMonth ? s.lastSync : null,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _FilterBar(state: s, cubit: cubit),
            ),
            SliverToBoxAdapter(
              child: ValueListenableBuilder<bool?>(
                valueListenable: widget.smsGranted,
                builder: (context, granted, _) => granted == false
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: NoticeBanner(
                          icon: Icons.sms_failed_outlined,
                          text:
                              'SMS access is off, so new payments are not '
                              'being logged',
                          action: 'Fix',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            if (s.reviewCount > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: NoticeBanner(
                    icon: Icons.rule_rounded,
                    text: s.reviewCount == 1
                        ? '1 bank message needs review'
                        : '${s.reviewCount} bank messages need review',
                    action: 'Review',
                    onTap: widget.onOpenReview,
                  ),
                ),
              ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SectionHead(
                span: s.txns.isEmpty
                    ? null
                    : '${dayMonth(s.txns.first.occurredAt)} — '
                          '${dayMonth(s.txns.last.occurredAt)}',
                background: c.bg,
                style: t.title,
                spanStyle: t.meta,
              ),
            ),
            if (showUpcoming) ...[
              const SliverToBoxAdapter(
                child: DayHeader(label: 'Upcoming · from bank AutoPay alerts'),
              ),
              SliverList.builder(
                itemCount: s.upcoming.length,
                itemBuilder: (_, i) => UpcomingRow(charge: s.upcoming[i]),
              ),
            ],
            if (s.loaded && s.txns.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  title: s.narrowed
                      ? 'Nothing matches these filters'
                      : 'No payments logged this month',
                  body: s.narrowed
                      ? null
                      : 'New bank alerts will appear here as they arrive.',
                ),
              )
            else
              ..._dayGroups(context, s.txns),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  List<Widget> _dayGroups(BuildContext context, List<TxnView> txns) {
    final now = DateTime.now();
    final groups = <DateTime, List<TxnView>>{};
    for (final t in txns) {
      groups.putIfAbsent(dateOnly(t.occurredAt), () => []).add(t);
    }
    return [
      for (final MapEntry(key: day, value: rows) in groups.entries) ...[
        SliverToBoxAdapter(
          child: DayHeader(
            label: dayLabel(day, now),
            trailing: _outLabel(rows),
          ),
        ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) => TxnRow(
            txn: rows[i],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TxnDetailScreen(txnId: rows[i].id),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  String? _outLabel(List<TxnView> rows) {
    final out = rows
        .where((r) => r.isDebit && r.countsInTotals)
        .fold(0, (sum, r) => sum + r.amountMinor);
    return out == 0 ? null : '${inr(out)} out';
  }
}

class _SectionHead extends SliverPersistentHeaderDelegate {
  _SectionHead({
    required this.span,
    required this.background,
    required this.style,
    required this.spanStyle,
  });

  final String? span;
  final Color background;
  final TextStyle style;
  final TextStyle spanStyle;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: background,
        // Fill the whole extent, or the pinned header's geometry is invalid.
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(
          children: [
            Expanded(child: Text('Transactions', style: style)),
            if (span != null) Text(span!, style: spanStyle),
          ],
        ),
      );

  @override
  bool shouldRebuild(_SectionHead old) =>
      old.span != span || old.background != background;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state, required this.cubit});

  final TransactionsState state;
  final TransactionsCubit cubit;

  @override
  Widget build(BuildContext context) {
    final f = state.filter;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          KFilterChip(
            label: _monthLabel(state.month),
            active: !state.isCurrentMonth,
            onTap: () => _pickMonth(context),
          ),
          const SizedBox(width: 8),
          KFilterChip(
            label: _accountsLabel(),
            active: f.accountIds.isNotEmpty,
            onTap: () => _pickAccounts(context),
          ),
          const SizedBox(width: 8),
          KFilterChip(
            label: _categoriesLabel(),
            active: f.categoryIds.isNotEmpty,
            onTap: () => _pickCategories(context),
          ),
          const SizedBox(width: 8),
          KFilterChip(
            label: switch (f.direction) {
              null => 'In & out',
              Direction.debit => 'Out',
              Direction.credit => 'In',
            },
            active: f.direction != null,
            onTap: () => _pickDirection(context),
          ),
        ],
      ),
    );
  }

  String _monthLabel(DateTime m) {
    final now = DateTime.now();
    if (m.year == now.year && m.month == now.month) return 'This month';
    final last = DateTime(now.year, now.month - 1);
    if (m.year == last.year && m.month == last.month) return 'Last month';
    return monthYear(m);
  }

  String _accountsLabel() {
    final ids = state.filter.accountIds;
    if (ids.isEmpty) return 'All accounts';
    if (ids.length == 1) {
      return state.accounts
              .where((a) => a.id == ids.first)
              .firstOrNull
              ?.short ??
          '1 account';
    }
    return '${ids.length} accounts';
  }

  String _categoriesLabel() {
    final ids = state.filter.categoryIds;
    if (ids.isEmpty) return 'Category';
    if (ids.length == 1) {
      return state.categories
              .where((c) => c.id == ids.first)
              .firstOrNull
              ?.name ??
          '1 category';
    }
    return '${ids.length} categories';
  }

  Future<void> _pickMonth(BuildContext context) async {
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in months)
              ListTile(
                title: Text(
                  _monthLabel(m) == monthYear(m)
                      ? monthYear(m)
                      : '${_monthLabel(m)} · ${monthYear(m)}',
                ),
                trailing: m == state.month
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) cubit.setMonth(picked);
  }

  Future<void> _pickAccounts(BuildContext context) async {
    final picked = await _multiPick(
      context,
      title: 'Accounts',
      options: {for (final a in state.accounts) a.id: a.long},
      selected: state.filter.accountIds,
    );
    if (picked != null) cubit.setAccounts(picked);
  }

  Future<void> _pickCategories(BuildContext context) async {
    final picked = await _multiPick(
      context,
      title: 'Categories',
      options: {for (final c in state.categories) c.id: c.name},
      icons: {for (final c in state.categories) c.id: categoryIcon(c.icon)},
      selected: state.filter.categoryIds,
    );
    if (picked != null) cubit.setCategories(picked);
  }

  Future<void> _pickDirection(BuildContext context) async {
    final options = <(Direction?, String)>[
      (null, 'In & out'),
      (Direction.debit, 'Money out'),
      (Direction.credit, 'Money in'),
    ];
    final picked = await showModalBottomSheet<(Direction?,)>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (d, label) in options)
              ListTile(
                title: Text(label),
                trailing: d == state.filter.direction
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, (d,)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) cubit.setDirection(picked.$1);
  }
}

/// Multi-select sheet; empty selection means "all".
Future<Set<String>?> _multiPick(
  BuildContext context, {
  required String title,
  required Map<String, String> options,
  required Set<String> selected,
  Map<String, IconData> icons = const {},
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  builder: (context) {
    final picked = {...selected};
    final t = context.kt;
    return StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: t.title)),
                    TextButton(
                      onPressed: () => Navigator.pop(context, <String>{}),
                      child: const Text('Show all'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (options.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Nothing here yet', style: t.meta),
                      ),
                    for (final MapEntry(:key, :value) in options.entries)
                      CheckboxListTile(
                        value: picked.contains(key),
                        title: Text(value, style: t.body),
                        secondary: icons[key] == null
                            ? null
                            : Icon(icons[key], color: context.k.text2),
                        onChanged: (v) => setSheet(
                          () => v! ? picked.add(key) : picked.remove(key),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, picked),
                    child: const Text('Apply'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
