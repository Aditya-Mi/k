import 'package:flutter/material.dart';

import '../../../data/db/app_database.dart' show Category;
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../backup/backup_parts.dart';

/// Opens New category (design 06j); the new category, or null if backed out.
Future<Category?> createCategory(BuildContext context) => Navigator.of(
  context,
).push<Category>(MaterialPageRoute(builder: (_) => const CategoryEditScreen()));

/// Last row of a category picker sheet: makes one, then closes the sheet
/// with what [result] maps it to (its id, or the row itself).
Widget newCategoryTile(
  BuildContext sheetContext,
  Object Function(Category) result,
) => ListTile(
  leading: Icon(Icons.add_rounded, color: sheetContext.k.text2),
  title: const Text('New category'),
  onTap: () async {
    final c = await createCategory(sheetContext);
    if (c != null && sheetContext.mounted) {
      Navigator.pop(sheetContext, result(c));
    }
  },
);

/// New category, or edit one ([category] set): name + a neutral icon.
/// Editing also offers Hide / Show.
class CategoryEditScreen extends StatefulWidget {
  const CategoryEditScreen({super.key, this.category});

  final Category? category;

  @override
  State<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends State<CategoryEditScreen> {
  final _ledger = getIt<LedgerRepository>();
  late final _name = TextEditingController(text: widget.category?.name);
  late String _icon = categoryIcons.containsKey(widget.category?.icon)
      ? widget.category!.icon
      : categoryIcons.keys.first;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    final existing = await _ledger.watchCategories(includeHidden: true).first;
    final clash = existing.any(
      (c) =>
          c.name.toLowerCase() == name.toLowerCase() &&
          c.id != widget.category?.id,
    );
    if (clash) {
      setState(() => _error = 'There is already a category called $name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_editing) {
      await _ledger.updateCategory(
        widget.category!.id,
        name: name,
        icon: _icon,
      );
      if (mounted) Navigator.pop(context, widget.category);
    } else {
      final c = await _ledger.addCategory(name, _icon);
      if (mounted) Navigator.pop(context, c);
    }
  }

  Future<void> _toggleHidden() async {
    final c = widget.category!;
    await _ledger.setCategoryHidden(c.id, !c.hidden);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final icons = categoryIcons.entries.toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_editing ? 'Edit category' : 'New category'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const FieldLabel('Name'),
          TextField(
            controller: _name,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: fieldBox(context, 'Rent, Gym, Pets…'),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: t.meta.copyWith(color: c.alert)),
          ],
          const SizedBox(height: 20),
          const FieldLabel('Icon'),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 52 / 44,
            mainAxisSpacing: 10,
            children: [
              for (final MapEntry(key: name, value: icon) in icons)
                Semantics(
                  label: name.replaceAll('_', ' '),
                  selected: name == _icon,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => setState(() => _icon = name),
                    child: Container(
                      decoration: name == _icon
                          ? BoxDecoration(
                              color: c.surface3,
                              border: Border.all(color: c.text),
                              borderRadius: BorderRadius.circular(22),
                            )
                          : null,
                      child: Icon(
                        icon,
                        color: name == _icon ? c.text : c.text2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _editing
                ? 'Renaming changes it on every payment filed here.'
                : 'Use “Use for all” on a payment to file a payee here.',
            style: t.meta.copyWith(color: c.text3, height: 1.35),
          ),
          if (_editing) ...[
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _toggleHidden,
                icon: Icon(
                  widget.category!.hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                label: Text(
                  widget.category!.hidden ? 'Show category' : 'Hide category',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.category!.hidden ? 'Hidden: past payments keep it.' : 'Past payments keep it. Payees filed here go uncategorized.',
              style: t.meta,
            ),
          ],
        ],
      ),
      bottomNavigationBar: BottomAction(
        icon: _editing ? Icons.check_rounded : Icons.add_rounded,
        label: _editing ? 'Save' : 'Add category',
        busy: _busy,
        onPressed: _save,
      ),
    );
  }
}
