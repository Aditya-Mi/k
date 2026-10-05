import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'add_account_screen.dart';

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
        actions: [
          IconButton(
            tooltip: 'Add account',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddAccountScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
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
                body:
                    'Accounts appear as bank messages arrive, or add one '
                    'with +.',
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
                'so the number is marked estimated. Set it yourself any time. '
                'Cash goes up with ATM withdrawals and down with cash payments '
                'you add; set it after counting your wallet.',
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
            if (all.length > 1 && !r.account.isCash)
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
      final minor = await showDialog<int>(
        context: context,
        builder: (_) => _BalanceDialog(
          title: isCredit ? 'Available limit now' : 'Balance now',
          initialMinor: r.balance?.amountMinor,
          // A card's available limit can't go below zero; a bank or cash
          // balance can (overdraft, design 10b).
          allowOverdrawn: !isCredit && !r.account.isCash,
        ),
      );
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
              if (o.account.id != r.account.id && !o.account.isCash)
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
    final meta = row.account.isCash
        ? (b == null || b.anchorAt.millisecondsSinceEpoch == 0
              ? 'ATM withdrawals add, cash payments you log subtract'
              : 'Counted by you ${_when(b.anchorAt)}'
                    '${b.estimated ? ', then ATM and cash payments' : ''}')
        : b == null
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
    final overdrawn =
        b != null && b.amountMinor < 0 && !isCredit && !row.account.isCash;
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
                  Text(overdrawn ? '$meta · overdrawn' : meta, style: t.meta),
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

/// Balance / limit entry. A bank balance can be overdrawn: the sign is a
/// choice, not a typed minus (design 10b). Pops the signed paise.
class _BalanceDialog extends StatefulWidget {
  const _BalanceDialog({
    required this.title,
    required this.initialMinor,
    required this.allowOverdrawn,
  });

  final String title;
  final int? initialMinor;
  final bool allowOverdrawn;

  @override
  State<_BalanceDialog> createState() => _BalanceDialogState();
}

class _BalanceDialogState extends State<_BalanceDialog> {
  late var _overdrawn = widget.allowOverdrawn && (widget.initialMinor ?? 0) < 0;
  late final _controller = TextEditingController(
    text: widget.initialMinor == null
        ? ''
        : (widget.initialMinor!.abs() / 100).toStringAsFixed(2),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final minor = parseAmountMinor(_controller.text);
    if (minor == null) return;
    Navigator.pop(context, _overdrawn ? -minor : minor);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.allowOverdrawn) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('In credit')),
                ButtonSegment(value: true, label: Text('Overdrawn')),
              ],
              selected: {_overdrawn},
              onSelectionChanged: (v) => setState(() => _overdrawn = v.single),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: _overdrawn ? '−₹ ' : '₹ ',
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_overdrawn) ...[
            const SizedBox(height: 8),
            Text(
              'Overdrawn: the account owes the bank this much. Later payments '
              'still add up from it.',
              style: t.meta,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
