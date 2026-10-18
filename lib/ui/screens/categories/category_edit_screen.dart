import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/db/app_database.dart' show Category;
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/k_sheet.dart';
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
  leading: Icon(Symbols.add, color: sheetContext.k.text2),
  title: const Text('New category'),
  onTap: () async {
    final c = await createCategory(sheetContext);
    if (c != null && sheetContext.mounted) {
      Navigator.pop(sheetContext, result(c));
    }
  },
);

/// Rows of a category picker (design 02h): top-level categories, each
/// followed by its sub-categories on a hairline rail; a check on
/// [selectedId].
List<Widget> categoryTiles(
  BuildContext context,
  List<Category> categories, {
  required String? selectedId,
  required void Function(Category) onPick,
}) {
  final c = context.k;
  final tree = categoryTree(categories);
  return [
    for (final (i, (cat, depth)) in tree.indexed)
      depth == 0
          ? ListTile(
              leading: Icon(categoryIcon(cat.icon), color: c.text2),
              title: Text(cat.name),
              trailing: cat.id == selectedId ? const Icon(Symbols.check) : null,
              onTap: () => onPick(cat),
            )
          : InkWell(
              onTap: () => onPick(cat),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 27),
                    SubRail(
                      last: i + 1 == tree.length || tree[i + 1].$2 == 0,
                      height: 48,
                    ),
                    Icon(categoryIcon(cat.icon), size: 20, color: c.text2),
                    const SizedBox(width: 12),
                    Expanded(child: Text(cat.name, style: context.kt.body)),
                    if (cat.id == selectedId) const Icon(Symbols.check),
                    const SizedBox(width: 24),
                  ],
                ),
              ),
            ),
  ];
}

/// The hairline that hangs a sub-category off its parent's icon.
class SubRail extends StatelessWidget {
  const SubRail({super.key, required this.last, required this.height});

  final bool last;
  final double height;

  @override
  Widget build(BuildContext context) {
    final line = context.k.outline;
    return SizedBox(
      width: 29,
      height: height,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: last ? height / 2 : height,
            child: ColoredBox(color: line),
          ),
          Positioned(
            left: 0,
            top: height / 2,
            width: 14,
            height: 1,
            child: ColoredBox(color: line),
          ),
        ],
      ),
    );
  }
}

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
  late String? _parentId = widget.category?.parentId;
  List<Category> _all = const [];

  bool get _editing => widget.category != null;

  @override
  void initState() {
    super.initState();
    _ledger.watchCategories(includeHidden: true).first.then((all) {
      if (mounted) setState(() => _all = all);
    });
  }

  /// Main categories this one can go inside.
  List<Category> get _parents => [
    for (final c in _all)
      if (c.parentId == null &&
          !c.hidden &&
          c.id != widget.category?.id &&
          !structuralCategoryIds.contains(c.id))
        c,
  ];

  /// Can't go inside another: k's structural ones, and ones that already
  /// hold sub-categories (one level only).
  bool get _canNest {
    final id = widget.category?.id;
    if (id == null) return true;
    return !structuralCategoryIds.contains(id) &&
        !_all.any((c) => c.parentId == id);
  }

  Future<void> _pickParent() async {
    final c = context.k;
    final picked = await showKSheet<String>(
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
              ListTile(
                leading: Icon(Symbols.do_not_disturb_on, color: c.text2),
                title: const Text('None'),
                subtitle: const Text('A main category'),
                trailing: _parentId == null ? const Icon(Symbols.check) : null,
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final p in _parents)
                ListTile(
                  leading: Icon(categoryIcon(p.icon), color: c.text2),
                  title: Text(p.name),
                  trailing: p.id == _parentId
                      ? const Icon(Symbols.check)
                      : null,
                  onTap: () => Navigator.pop(context, p.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _parentId = picked.isEmpty ? null : picked);
    }
  }

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
        parentId: _canNest ? Value(_parentId) : const Value.absent(),
      );
      if (mounted) Navigator.pop(context, widget.category);
    } else {
      final c = await _ledger.addCategory(name, _icon, parentId: _parentId);
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_editing ? 'Edit category' : 'New category'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const FieldLabel('Name'),
          TextField(
            style: context.kt.input,
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
          if (_canNest && _all.isNotEmpty) ...[
            const SizedBox(height: 20),
            const FieldLabel('Inside'),
            _InsideBox(
              parent: _all.where((x) => x.id == _parentId).firstOrNull,
              onTap: _pickParent,
            ),
            const SizedBox(height: 6),
            Text(
              _parentId == null
                  ? 'Optional. Put it inside another category to add them '
                        'up together in Summary.'
                  : 'Its payments also count toward '
                        '${_all.where((x) => x.id == _parentId).firstOrNull?.name ?? 'it'} '
                        'in Summary.',
              style: t.meta.copyWith(color: c.text3, height: 1.35),
            ),
          ],
          const SizedBox(height: 20),
          const FieldLabel('Icon'),
          const SizedBox(height: 4),
          for (final (title, icons) in categoryIconGroups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(title, style: t.meta.copyWith(color: c.text2)),
            ),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 52 / 44,
              mainAxisSpacing: 10,
              children: [
                for (final MapEntry(key: name, value: icon) in icons.entries)
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
                          fill: name == _icon ? 1 : 0,
                          color: name == _icon ? c.text : c.text2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
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
                      ? Symbols.visibility
                      : Symbols.visibility_off,
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
        icon: _editing ? Symbols.check : Symbols.add,
        label: _editing ? 'Save' : 'Add category',
        busy: _busy,
        onPressed: _save,
      ),
    );
  }
}

class _InsideBox extends StatelessWidget {
  const _InsideBox({required this.parent, required this.onTap});

  final Category? parent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: c.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (parent != null) ...[
              Icon(categoryIcon(parent!.icon), size: 20, color: c.text2),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                parent?.name ?? 'None, a main category',
                style: t.input.copyWith(
                  color: parent == null ? c.text3 : c.text,
                ),
              ),
            ),
            Icon(Symbols.chevron_right, size: 20, color: c.text3),
          ],
        ),
      ),
    );
  }
}
