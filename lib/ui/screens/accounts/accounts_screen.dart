import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../../../data/db/enums.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/text_prompt.dart';

typedef _Row = ({AccountView account, AccountBalance? balance});

/// Own accounts with their latest balance (or card available limit).
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ledger = getIt<LedgerRepository>();
    final t = context.kt;
    final c = context.k;
    final rows = Rx.combineLatest2(
      ledger.watchAccounts(),
      ledger.watchBalances(),
      (accounts, balances) => [
        for (final a in accounts) (account: a, balance: balances[a.id]),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Accounts'),
      ),
      body: StreamBuilder<List<_Row>>(
        stream: rows,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const SizedBox.shrink();
          if (list.isEmpty) {
            return const Center(
              child: EmptyState(
                title: 'No accounts yet',
                body: 'Accounts appear as bank messages arrive.',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final r in list)
                _AccountRow(row: r, onTap: () => _actions(context, r, list)),
              const SizedBox(height: 24),
              Text(
                'Balances come from your banks\' messages. When a message has '
                'none, k adds up the payments since the last figure it saw, '
                'so the number is marked estimated. Set it yourself any time.',
                style: t.meta.copyWith(color: c.text3),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<void> _actions(BuildContext context, _Row r, List<_Row> all) async {
    final isCredit = r.account.type == AccountType.creditCard;
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 0),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(isCredit ? 'Set available limit' : 'Set balance'),
              onTap: () => Navigator.pop(context, 1),
            ),
            if (all.length > 1)
              ListTile(
                leading: const Icon(Icons.call_merge_rounded),
                title: const Text('Merge into another account'),
                subtitle: const Text('Same money, e.g. a debit card'),
                onTap: () => Navigator.pop(context, 2),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    final ledger = getIt<LedgerRepository>();
    if (choice == 2) {
      await _merge(context, r, all);
      return;
    }
    if (choice == 0) {
      final name = await _prompt(
        context,
        title: 'Rename account',
        initial: r.account.nickname ?? '',
        hint: r.account.long,
      );
      if (name != null) await ledger.renameAccount(r.account.id, name);
    } else {
      final text = await _prompt(
        context,
        title: isCredit ? 'Available limit now' : 'Balance now',
        initial: r.balance == null
            ? ''
            : (r.balance!.amountMinor / 100).toStringAsFixed(2),
        hint: '0.00',
        numeric: true,
      );
      final minor = text == null ? null : parseAmountMinor(text);
      if (minor != null) {
        await ledger.setManualBalance(r.account.id, minor, DateTime.now());
      }
    }
  }

  Future<void> _merge(BuildContext context, _Row r, List<_Row> all) async {
    final target = await showModalBottomSheet<AccountView>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Merge ${r.account.short} into',
                style: context.kt.title,
              ),
            ),
            for (final o in all)
              if (o.account.id != r.account.id)
                ListTile(
                  title: Text(o.account.long),
                  onTap: () => Navigator.pop(context, o.account),
                ),
          ],
        ),
      ),
    );
    if (target == null || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge accounts?'),
        content: Text(
          'Payments on ${r.account.long} move to ${target.long}, and future '
          'messages for ${r.account.short} are logged there. This can\'t be '
          'undone from the app yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await getIt<LedgerRepository>().mergeAccount(r.account.id, target.id);
    }
  }

  Future<String?> _prompt(
    BuildContext context, {
    required String title,
    required String initial,
    required String hint,
    bool numeric = false,
  }) async {
    return promptText(
      context,
      title: title,
      initial: initial,
      hint: hint,
      numeric: numeric,
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.row, required this.onTap});

  final _Row row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final b = row.balance;
    final isCredit = row.account.type == AccountType.creditCard;
    final label = isCredit ? 'Available limit' : 'Balance';
    final meta = b == null
        ? 'No balance yet · tap to set'
        : switch (b.source) {
            BalanceSource.bank when b.estimated =>
              '$label · estimated from ${b.estimatedFrom} '
                  '${b.estimatedFrom == 1 ? 'payment' : 'payments'} since '
                  '${_when(b.anchorAt)}',
            BalanceSource.bank => '$label · bank, ${_when(b.anchorAt)}',
            BalanceSource.manual when b.estimated =>
              '$label · set by you ${_when(b.anchorAt)}, estimated since',
            BalanceSource.manual => '$label · set by you ${_when(b.anchorAt)}',
          };
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.outline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.account.long, style: t.body),
                  if (row.account.includes.isNotEmpty)
                    Text(
                      'Includes ${row.account.includes.join(', ')}',
                      style: t.meta,
                    ),
                  const SizedBox(height: 2),
                  Text(meta, style: t.meta),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text(
              b == null
                  ? '—'
                  : '${b.amountMinor < 0 ? '−' : ''}'
                        '${inr(b.amountMinor, paise: true)}',
              style: t.amountRow.copyWith(
                color: b == null || b.estimated ? c.text2 : c.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _when(DateTime d) => '${dayMonth(d)}, ${hhmm(d)}';
}
