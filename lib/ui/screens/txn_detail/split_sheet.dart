import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../../../data/db/app_database.dart' show Category;
import '../../../data/repositories/ledger_models.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/k_sheet.dart';
import '../backup/backup_parts.dart';
import '../categories/category_edit_screen.dart';

typedef SplitParts = List<({String categoryId, int amountMinor})>;

/// Split a payment (design 02g): parts under other categories, the rest
/// staying in the payment's own. Returns the parts to save (empty = no
/// split), or null if backed out.
Future<SplitParts?> showSplitSheet(
  BuildContext context,
  TxnView txn,
  List<Category> categories,
) => showKSheet<SplitParts>(
  context: context,
  isScrollControlled: true,
  avoidKeyboard: true,
  builder: (_) => _SplitSheet(txn: txn, categories: categories),
);

class _Part {
  _Part(this.category, String amount)
    : amount = TextEditingController(text: amount);

  Category? category;
  final TextEditingController amount;

  int? get minor {
    final m = parseAmountMinor(amount.text.trim());
    return m == null || m <= 0 ? null : m;
  }
}

class _SplitSheet extends StatefulWidget {
  const _SplitSheet({required this.txn, required this.categories});

  final TxnView txn;
  final List<Category> categories;

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  late final List<_Part> _parts = widget.txn.isSplit
      ? [
          for (final p in widget.txn.splits)
            _Part(p.category, _rupees(p.amountMinor)),
        ]
      : [_Part(null, '')];

  static String _rupees(int minor) =>
      minor % 100 == 0 ? '${minor ~/ 100}' : (minor / 100).toStringAsFixed(2);

  @override
  void dispose() {
    for (final p in _parts) {
      p.amount.dispose();
    }
    super.dispose();
  }

  int get _partsMinor => _parts.fold(0, (s, p) => s + (p.minor ?? 0));
  int get _restMinor => widget.txn.amountMinor - _partsMinor;

  /// Why Save can't go yet, or null.
  String? get _problem {
    if (_restMinor < 0) {
      return 'Parts add up to more than ${inr(widget.txn.amountMinor, paise: true)}';
    }
    for (final p in _parts) {
      if (p.category == null) return 'Pick a category for each part';
      if (p.minor == null) return 'Give each part an amount';
    }
    return null;
  }

  Future<void> _pick(_Part part) async {
    final picked = await showKSheet<Category>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ...categoryTiles(
                context,
                [
                  for (final c in widget.categories)
                    if (!structuralCategoryIds.contains(c.id)) c,
                ],
                selectedId: part.category?.id,
                onPick: (cat) => Navigator.pop(context, cat),
              ),
              newCategoryTile(context, (c) => c),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => part.category = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final txn = widget.txn;
    final problem = _problem;
    final removing = _parts.isEmpty;
    return KDialog(
      title: Text('Split ${inr(txn.amountMinor, paise: true)}'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${txn.payee} · each part counts in its own category'),
          const SizedBox(height: 16),
          _Row(
            chip: _Chip(category: txn.category),
            amount: Container(
              height: 44,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                inr(_restMinor < 0 ? 0 : _restMinor, paise: true),
                style: t.amountRow.copyWith(color: c.text2),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "The rest stays in the payment's category.",
            style: t.meta.copyWith(color: c.text3),
          ),
          for (final p in _parts) ...[
            const SizedBox(height: 10),
            _Row(
              chip: _Chip(category: p.category, onTap: () => _pick(p)),
              amount: TextField(
                controller: p.amount,
                autofocus: p.amount.text.isEmpty && _parts.length == 1,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                textAlign: TextAlign.right,
                style: t.amountInput.copyWith(fontSize: 17),
                decoration: fieldBox(context, '0').copyWith(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  prefixText: '₹ ',
                ),
                onChanged: (_) => setState(() {}),
              ),
              remove: IconButton(
                tooltip: 'Remove part',
                icon: Icon(Symbols.close, size: 18, color: c.text2),
                onPressed: () => setState(() {
                  _parts.remove(p);
                  p.amount.dispose();
                }),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _parts.add(_Part(null, ''))),
              icon: const Icon(Symbols.add, size: 18),
              label: const Text('Add a part'),
              style: TextButton.styleFrom(foregroundColor: c.text),
            ),
          ),
          if (problem != null && _parts.any((p) => p.amount.text.isNotEmpty))
            Text(problem, style: t.meta.copyWith(color: c.alert)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem != null
              ? null
              : () => Navigator.pop(
                  context,
                  <({String categoryId, int amountMinor})>[
                    for (final p in _parts)
                      (categoryId: p.category!.id, amountMinor: p.minor!),
                  ],
                ),
          child: Text(removing ? 'Remove split' : 'Save split'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.chip, required this.amount, this.remove});

  final Widget chip;
  final Widget amount;
  final Widget? remove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: chip),
      const SizedBox(width: 10),
      SizedBox(width: 132, child: amount),
      SizedBox(width: 40, child: remove),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.category, this.onTap});

  final Category? category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Material(
      color: c.surface3,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(categoryIcon(category?.icon), size: 18, color: c.text),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category?.name ??
                      (onTap == null ? 'Uncategorized' : 'Choose'),
                  style: t.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: category == null && onTap != null ? c.text2 : c.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(Symbols.chevron_right, size: 16, color: c.text3),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
