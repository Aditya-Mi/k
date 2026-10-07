import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/emis/emi_service.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/note_chip.dart';
import 'emi_form_screen.dart';

/// One EMI (design 13): icon, name over "8 of 12 · ends Jan 2027", the
/// instalment's chip and amount, and a bar filled by instalments paid.
class EmiRow extends StatelessWidget {
  const EmiRow({super.key, required this.emi, this.showAccount = true});

  final EmiView emi;

  /// Off on the card's own screen.
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final e = emi;
    final next = e.nextDueAt;
    final meta = [
      if (showAccount && e.account != null) e.account!.short,
      '${e.paid} of ${e.row.count}${e.isCard ? '' : ' paid'}',
      if (next != null && !e.isCard)
        'next ${dayShort(next)}'
      else
        'ends ${monthShort(e.endsAt, DateTime.now())}',
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmiFormScreen.edit(emi: e)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.outline),
                  ),
                  child: Icon(
                    e.isCard ? Symbols.credit_card : Symbols.home,
                    size: 20,
                    color: c.text2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        style: t.body.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(meta, style: t.meta),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                NoteChip(amountMinor: e.row.amountMinor),
                const SizedBox(width: 12),
                Text(inrRow(e.row.amountMinor), style: t.amountRow),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: c.surface3),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: e.row.count == 0
                            ? 0
                            : (e.paid / e.row.count).clamp(0, 1).toDouble(),
                        child: ColoredBox(color: c.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section head for EMIs: "EMIs" and "₹4,210 a month".
class EmiHead extends StatelessWidget {
  const EmiHead({super.key, required this.emis});

  final List<EmiView> emis;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final month = emis.fold(0, (s, e) => s + e.row.amountMinor);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text('EMIs', style: t.title)),
          Text('${inr(month)} a month', style: t.meta),
        ],
      ),
    );
  }
}
