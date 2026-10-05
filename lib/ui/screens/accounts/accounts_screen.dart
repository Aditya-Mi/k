import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../../../data/emis/emi_service.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/text_prompt.dart';
import '../settings/settings_screen.dart';
import 'add_account_screen.dart';
import 'card_screen.dart';

typedef AccountRowData = ({
  AccountView account,
  AccountBalance? balance,
  List<EmiView> emis,
});

/// Own accounts with their latest balance; cards show what's owed (design
/// 12). A tab on home ([asTab]: no back, settings in the bar).
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, this.asTab = false});

  final bool asTab;

  static Stream<List<AccountRowData>> rows() {
    final ledger = getIt<LedgerRepository>();
    return Rx.combineLatest3(
      ledger.watchAccounts(),
      ledger.watchBalances(),
      getIt<EmiService>().watch(),
      (accounts, balances, emis) => [
        for (final a in accounts)
          (
            account: a,
            balance: balances[a.id],
            emis: [
              for (final e in emis)
                if (e.row.accountId == a.id) e,
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: asTab
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
        titleSpacing: asTab ? 20 : null,
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Add account',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddAccountScreen()),
            ),
          ),
          if (asTab)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<AccountRowData>>(
        stream: rows(),
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
          final banks = [
            for (final r in list)
              if (!r.account.isCreditCard && !r.account.isCash) r,
          ];
          final cards = [
            for (final r in list)
              if (r.account.isCreditCard) r,
          ];
          final cash = [
            for (final r in list)
              if (r.account.isCash) r,
          ];
          Widget head(String text) => Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Text(
              text,
              style: t.meta.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          );
          void open(AccountRowData r) => r.account.isCreditCard
              ? Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CardScreen(accountId: r.account.id),
                  ),
                )
              : accountActions(context, r, list);
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (banks.isNotEmpty) ...[
                head('Bank accounts'),
                for (final r in banks)
                  _AccountRow(row: r, onTap: () => open(r)),
              ],
              if (cards.isNotEmpty) ...[
                head('Credit cards'),
                for (final r in cards)
                  _AccountRow(row: r, onTap: () => open(r)),
              ],
              if (cash.isNotEmpty) ...[
                head('Cash'),
                for (final r in cash) _AccountRow(row: r, onTap: () => open(r)),
              ],
              const SizedBox(height: 24),
              Text(
                'Balances come from your banks\' messages; k estimates '
                'between them. A card shows what you owe: its limit minus the '
                'available limit the bank reports. Paying the bill moves '
                'money from savings to the card, so it is not counted as '
                'spent. Cash goes up with ATM withdrawals and down with cash '
                'payments you add.',
                style: t.meta.copyWith(color: c.text3),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// Rename, set balance (or a card's limits), merge.
Future<void> accountActions(
  BuildContext context,
  AccountRowData r,
  List<AccountRowData> all,
) async {
  final isCredit = r.account.isCreditCard;
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
          if (isCredit)
            ListTile(
              leading: const Icon(Icons.credit_score_outlined),
              title: const Text('Set card limit'),
              onTap: () => Navigator.pop(context, 3),
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
  switch (choice) {
    case 2:
      await _merge(context, r, all);
    case 0:
      final name = await promptText(
        context,
        title: 'Rename account',
        initial: r.account.nickname ?? '',
        hint: r.account.long,
      );
      if (name != null) await ledger.renameAccount(r.account.id, name);
    case 3:
      final minor = await showDialog<int>(
        context: context,
        builder: (_) => BalanceDialog(
          title: 'Card limit',
          initialMinor: r.account.creditLimitMinor,
          allowOverdrawn: false,
          note:
              'The total limit on the card. With the available limit the '
              'bank reports, k works out what you owe.',
        ),
      );
      if (minor != null) await ledger.setCreditLimit(r.account.id, minor);
    default:
      final minor = await showDialog<int>(
        context: context,
        builder: (_) => BalanceDialog(
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

Future<void> _merge(
  BuildContext context,
  AccountRowData r,
  List<AccountRowData> all,
) async {
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

/// "₹85,420.50 available of ₹1,00,000"; without a limit, the bank's figure.
String cardLimitLine(AccountView a, AccountBalance? b) {
  if (b == null) return 'No available limit yet · tap to set';
  final limit = a.creditLimitMinor;
  if (limit == null) return '${inr(b.amountMinor, paise: true)} available';
  return '${inr(b.amountMinor, paise: true)} available of ${inr(limit)}';
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.row, required this.onTap});

  final AccountRowData row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final b = row.balance;
    final a = row.account;
    if (a.isCreditCard) return _cardRow(context, a, b);
    const label = 'Balance';
    final meta = a.isCash
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
    final overdrawn = b != null && b.amountMinor < 0 && !a.isCash;
    return _shell(
      c,
      children: [
        Text(a.long, style: t.body),
        if (a.includes.isNotEmpty)
          Text('Includes ${a.includes.join(', ')}', style: t.meta),
        const SizedBox(height: 2),
        Text(overdrawn ? '$meta · overdrawn' : meta, style: t.meta),
        if (row.emis.isNotEmpty) _emiLine(t, c),
      ],
      trailing: Text(
        b == null
            ? '—'
            : '${b.amountMinor < 0 ? '−' : ''}'
                  '${inr(b.amountMinor, paise: true)}',
        style: t.amountRow.copyWith(
          color: b == null || b.estimated ? c.text2 : c.text,
        ),
      ),
    );
  }

  Widget _cardRow(BuildContext context, AccountView a, AccountBalance? b) {
    final c = context.k;
    final t = context.kt;
    final owed = a.owedMinor(b?.amountMinor);
    final limit = a.creditLimitMinor;
    return _shell(
      c,
      children: [
        Text(a.long, style: t.body),
        const SizedBox(height: 2),
        Text(
          owed == null && b != null && limit == null
              ? '${cardLimitLine(a, b)} · set the limit to see what you owe'
              : cardLimitLine(a, b),
          style: t.meta,
        ),
        if (owed != null && limit != null && limit > 0) ...[
          const SizedBox(height: 6),
          UsedBar(fraction: owed / limit),
        ],
        if (row.emis.isNotEmpty) _emiLine(t, c),
      ],
      trailing: owed == null
          ? Text(
              b == null ? '—' : inr(b.amountMinor, paise: true),
              style: t.amountRow.copyWith(color: c.text2),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(inr(owed, paise: true), style: t.amountRow),
                Text('owed', style: t.meta),
              ],
            ),
    );
  }

  Widget _emiLine(KText t, KColors c) {
    final month = row.emis.fold(0, (s, e) => s + e.row.amountMinor);
    final n = row.emis.length;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$n ${n == 1 ? 'EMI' : 'EMIs'} · ${inr(month)} a month',
        style: t.meta.copyWith(color: c.text3),
      ),
    );
  }

  Widget _shell(
    KColors c, {
    required List<Widget> children,
    required Widget trailing,
  }) => InkWell(
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
              children: children,
            ),
          ),
          const SizedBox(width: 14),
          trailing,
        ],
      ),
    ),
  );

  String _when(DateTime d) => '${dayMonth(d)}, ${hhmm(d)}';
}

/// How much of a card's limit is used: text-coloured fill on surface-3
/// (neutral; inks are only for amounts).
class UsedBar extends StatelessWidget {
  const UsedBar({super.key, required this.fraction, this.height = 4});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: c.surface3),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0, 1).toDouble(),
              child: ColoredBox(color: c.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Balance / limit entry. A bank balance can be overdrawn: the sign is a
/// choice, not a typed minus (design 10b). Pops the signed paise.
class BalanceDialog extends StatefulWidget {
  const BalanceDialog({
    super.key,
    this.note,
    required this.title,
    required this.initialMinor,
    required this.allowOverdrawn,
  });

  final String title;
  final int? initialMinor;
  final bool allowOverdrawn;

  /// Explains the figure under the field.
  final String? note;

  @override
  State<BalanceDialog> createState() => _BalanceDialogState();
}

class _BalanceDialogState extends State<BalanceDialog> {
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
          if (widget.note != null) ...[
            const SizedBox(height: 8),
            Text(widget.note!, style: t.meta),
          ],
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
