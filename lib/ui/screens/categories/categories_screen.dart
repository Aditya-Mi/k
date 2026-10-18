import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/db/app_database.dart' show Category;
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../settings/settings_parts.dart';
import 'category_edit_screen.dart';

/// Categories (design 06i, 06i-b): yours, built in, hidden; sub-categories
/// hang under their parent on a hairline rail. Tap to rename, change the
/// icon, move inside another or hide; + adds one.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

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
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'New category',
            icon: const Icon(Symbols.add),
            onPressed: () => createCategory(context),
          ),
        ],
      ),
      body: StreamBuilder<List<(Category, int)>>(
        stream: getIt<LedgerRepository>().watchCategoryUse(),
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const SizedBox.shrink();
          final shown = [
            for (final e in all)
              if (!e.$1.hidden) e,
          ];
          final ids = {for (final e in shown) e.$1.id};
          // Sub-categories sit under their parent, in the parent's section.
          bool top((Category, int) e) =>
              e.$1.parentId == null || !ids.contains(e.$1.parentId);
          List<(Category, int)> kids(Category p) => [
            for (final e in shown)
              if (!top(e) && e.$1.parentId == p.id) e,
          ];
          final yours = [
            for (final e in shown)
              if (top(e) && !e.$1.isSystem) e,
          ];
          final builtIn = [
            for (final e in shown)
              if (top(e) && e.$1.isSystem) e,
          ];
          final hidden = [
            for (final e in all)
              if (e.$1.hidden) e,
          ];

          void open(Category cat) => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => CategoryEditScreen(category: cat),
            ),
          );
          String count(int n) =>
              '${grouped(n)} ${n == 1 ? 'payment' : 'payments'}';

          Widget row((Category, int) e, {int inside = 0}) => Opacity(
            opacity: e.$1.hidden ? 0.55 : 1,
            child: SettingsItem(
              icon: categoryIcon(e.$1.icon),
              title: e.$1.name,
              subtitle: [
                if (e.$1.hidden) 'Hidden',
                if (inside > 0) '$inside inside',
                if (!e.$1.hidden || e.$2 > 0)
                  e.$2 == 0
                      ? (inside > 0
                            ? 'none of its own'
                            : e.$1.isSystem
                            ? 'No payments yet'
                            : 'Added by you')
                      : count(e.$2),
              ].join(' · '),
              onTap: () => open(e.$1),
              trailing: const SettingsChevron(),
            ),
          );

          List<Widget> branch((Category, int) e) {
            final inside = kids(e.$1);
            return [
              row(e, inside: inside.length),
              for (final (i, k) in inside.indexed)
                _SubItem(
                  category: k.$1,
                  subtitle: [
                    k.$2 == 0 ? 'No payments yet' : count(k.$2),
                    if (!k.$1.isSystem && e.$1.isSystem) 'yours',
                  ].join(' · '),
                  last: i == inside.length - 1,
                  onTap: () => open(k.$1),
                ),
            ];
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SettingsHead('Yours'),
              if (yours.isEmpty)
                SettingsItem(
                  icon: Symbols.add,
                  iconColor: c.text2,
                  title: 'Add your own',
                  subtitle: 'Rent, Gym, Pets: anything k doesn’t have',
                  onTap: () => createCategory(context),
                ),
              for (final e in yours) ...branch(e),
              const SettingsHead('Built in', note: 'Rename or hide'),
              for (final e in builtIn) ...branch(e),
              if (hidden.isNotEmpty) ...[
                const SettingsHead('Hidden'),
                for (final e in hidden) row(e),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(
                  'Put a category inside another from its edit screen. '
                  'Summary adds them up under the outer one.',
                  style: t.meta.copyWith(color: c.text3, height: 1.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A sub-category row: hung off its parent's icon by a hairline rail.
class _SubItem extends StatelessWidget {
  const _SubItem({
    required this.category,
    required this.subtitle,
    required this.last,
    required this.onTap,
  });

  final Category category;
  final String subtitle;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 31, right: 20),
        child: Row(
          children: [
            SubRail(last: last, height: 56),
            Icon(categoryIcon(category.icon), size: 20, color: c.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.name, style: t.body),
                  Text(subtitle, style: t.meta.copyWith(color: c.text2)),
                ],
              ),
            ),
            const SettingsChevron(),
          ],
        ),
      ),
    );
  }
}
