import 'package:flutter/material.dart';

import '../../data/repositories/ledger_models.dart';
import '../format.dart';
import '../theme/k_theme.dart';
import 'note_chip.dart';

/// Chip · payee over meta · amount. Columns never move between row states.
class TxnRow extends StatelessWidget {
  const TxnRow({super.key, required this.txn, this.onTap, this.title});

  final TxnView txn;
  final VoidCallback? onTap;

  /// Replaces the payee (a subscription's charges list shows the date).
  final String? title;

  @override
  Widget build(BuildContext context) {
    final meta = txn.isTransfer
        ? [
            txn.transferRoute,
            if (txn.addedByUser) 'added by you',
            hhmm(txn.occurredAt),
          ].join(' · ')
        : [
            txn.category?.name ?? 'Uncategorized',
            if (txn.account != null) txn.account!.short,
            hhmm(txn.occurredAt),
          ].join(' · ');
    final title = this.title ?? (txn.isTransfer ? 'Self transfer' : txn.payee);
    return _RowShell(
      onTap: onTap,
      chip: NoteChip(
        amountMinor: txn.amountMinor,
        style: txn.isDebit ? NoteChipStyle.filled : NoteChipStyle.outlined,
      ),
      title: title,
      meta: meta,
      trailing: [
        if (txn.isTransfer)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Between your own accounts, not counted as spent',
              child: Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: context.k.text2,
              ),
            ),
          ),
        if (txn.isCash && txn.isDebit)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Paid from cash, already counted at the ATM',
              child: Icon(
                Icons.payments_outlined,
                size: 16,
                color: context.k.text2,
              ),
            ),
          ),
        if (txn.merged)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: 'Merged from ${txn.sourceCount} bank messages',
              child: Icon(
                Icons.merge_rounded,
                size: 16,
                color: context.k.text2,
              ),
            ),
          ),
        Text(
          inrRow(txn.amountMinor, plus: !txn.isDebit),
          style: context.kt.amountRow,
        ),
      ],
      semantics:
          '$title, ${txn.isTransfer
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
        style: NoteChipStyle.pending,
      ),
      title: charge.name,
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
    this.onTap,
  });

  final Widget chip;
  final String title;
  final String meta;
  final List<Widget> trailing;
  final String semantics;
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
                      style: t.body,
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
