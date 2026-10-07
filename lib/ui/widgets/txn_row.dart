import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/repositories/ledger_models.dart';
import '../format.dart';
import '../theme/k_theme.dart';
import 'k_icons.dart';
import 'note_chip.dart';

/// Chip · payee over meta · amount. Columns never move between row states.
class TxnRow extends StatelessWidget {
  const TxnRow({
    super.key,
    required this.txn,
    this.onTap,
    this.onLongPress,
    this.title,
    this.onCard = false,
  });

  final TxnView txn;
  final VoidCallback? onTap;

  /// Quick actions sheet (Transactions, design 01d).
  final VoidCallback? onLongPress;

  /// Replaces the payee (a subscription's charges list shows the date).
  final String? title;

  /// Card screen (design 12b): no day headers, so rows carry the date, and
  /// the bill reads "Bill payment · Axis ··1234 · 2 Oct · not spent".
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    final cardBill = onCard && txn.isCardBill;
    final when = onCard
        ? '${dayMonth(txn.occurredAt)}, ${hhmm(txn.occurredAt)}'
        : hhmm(txn.occurredAt);
    final meta = cardBill
        ? [
            txn.isDebit
                ? txn.account?.short
                : txn.partnerAccount?.short ?? 'From your bank',
            dayMonth(txn.occurredAt),
            'not spent',
          ].nonNulls.join(' · ')
        : txn.isAtmWithdrawal
        ? ['${txn.account?.short ?? 'Bank'} → Cash', when].join(' · ')
        : txn.isTransfer
        ? [
            txn.transferRoute,
            if (txn.addedByUser) 'added by you',
            when,
          ].join(' · ')
        : [
            if (txn.isRefund)
              'Refund'
            else
              txn.category?.name ?? 'Uncategorized',
            if (txn.emi != null)
              txn.emi!.isPurchase ? 'EMI ×${txn.emi!.count}' : 'EMI',
            if (txn.account != null && !onCard) txn.account!.short,
            when,
          ].join(' · ');
    final title =
        this.title ??
        (cardBill
            ? 'Bill payment'
            : txn.isCardBill
            ? 'Card bill payment'
            : txn.isAtmWithdrawal
            ? 'ATM withdrawal'
            : txn.isTransfer
            ? 'Self transfer'
            : txn.payee);
    return _RowShell(
      onTap: onTap,
      onLongPress: onLongPress,
      chip: NoteChip(
        amountMinor: txn.amountMinor,
        style: txn.isDebit ? NoteChipStyle.filled : NoteChipStyle.outlined,
      ),
      title: title,
      meta: meta,
      trailing: [
        if ((txn.isTransfer && !cardBill) || txn.isAtmWithdrawal)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: txn.isAtmWithdrawal
                  ? 'To cash in hand, not counted as spent'
                  : txn.isCardBill
                  ? 'Card bill, not counted as spent'
                  : 'Own accounts, not counted as spent',
              child: KIcon(KIcons.transfer, size: 16, color: context.k.text2),
            ),
          ),
        if (txn.isCash && txn.isDebit)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Paid in cash',
              child: Icon(Symbols.payments, size: 16, color: context.k.text2),
            ),
          ),
        if (txn.merged)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: '${txn.sourceCount} messages merged',
              child: KIcon(KIcons.merged, size: 16, color: context.k.text2),
            ),
          ),
        Text(
          inrRow(txn.amountMinor, plus: !txn.isDebit),
          style: context.kt.amountRow,
        ),
      ],
      semantics:
          '$title, ${txn.isTransfer || txn.isAtmWithdrawal
              ? 'moved'
              : txn.isDebit
              ? 'paid'
              : 'received'} '
          '${inrRow(txn.amountMinor)}, $meta',
    );
  }
}

/// AutoPay / mandate charge that has not happened yet.
class UpcomingRow extends StatelessWidget {
  const UpcomingRow({super.key, required this.charge});

  final UpcomingView charge;

  @override
  Widget build(BuildContext context) {
    final meta = [
      'Due ${dayShort(charge.dueDate)}',
      'AutoPay',
      ?charge.bankShort,
    ].join(' · ');
    return _RowShell(
      chip: NoteChip(
        amountMinor: charge.amountMinor,
        style: NoteChipStyle.upcoming,
      ),
      title: charge.name,
      titleColor: context.k.text2,
      meta: meta,
      trailing: [
        Text(
          inrRow(charge.amountMinor),
          style: context.kt.amountRow.copyWith(color: context.k.text2),
        ),
      ],
      semantics:
          '${charge.name}, ${inrRow(charge.amountMinor)} upcoming, $meta',
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.chip,
    required this.title,
    required this.meta,
    required this.trailing,
    required this.semantics,
    this.titleColor,
    this.onTap,
    this.onLongPress,
  });

  final Widget chip;
  final String title;
  final String meta;
  final List<Widget> trailing;
  final String semantics;

  /// text-2 for an upcoming row (not paid yet).
  final Color? titleColor;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return Semantics(
      label: semantics,
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              chip,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: titleColor == null
                          ? t.body
                          : t.body.copyWith(color: titleColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: t.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}
