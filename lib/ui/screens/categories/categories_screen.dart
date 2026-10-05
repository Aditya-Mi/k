import 'package:flutter/material.dart';

import '../../../data/db/app_database.dart' show Category;
import '../../../data/repositories/ledger_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../settings/settings_parts.dart';
import 'category_edit_screen.dart';

/// Categories (design 06i): yours, built in, hidden. Tap to rename, change
/// the icon or hide; + adds one.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'New category',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => createCategory(context),
          ),
        ],
      ),
      body: StreamBuilder<List<(Category, int)>>(
        stream: getIt<LedgerRepository>().watchCategoryUse(),
        builder: (context, snap) {
          final all = snap.data;
          if (all == null) return const SizedBox.shrink();
          final yours = [
            for (final e in all)
              if (!e.$1.isSystem && !e.$1.hidden) e,
          ];
          final builtIn = [
            for (final e in all)
              if (e.$1.isSystem && !e.$1.hidden) e,
          ];
          final hidden = [
            for (final e in all)
              if (e.$1.hidden) e,
          ];
          Widget row((Category, int) e) => Opacity(
            opacity: e.$1.hidden ? 0.55 : 1,
            child: SettingsItem(
              icon: categoryIcon(e.$1.icon),
              title: e.$1.name,
              subtitle: [
                if (e.$1.hidden) 'Hidden · not offered when you pick',
                if (!e.$1.hidden || e.$2 > 0)
                  e.$2 == 0
                      ? (e.$1.isSystem ? 'No payments yet' : 'Added by you')
                      : '${grouped(e.$2)} ${e.$2 == 1 ? 'payment' : 'payments'}',
              ].join(' · '),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CategoryEditScreen(category: e.$1),
                ),
              ),
              trailing: const SettingsChevron(),
            ),
          );
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SettingsHead('Yours'),
              if (yours.isEmpty)
                SettingsItem(
                  icon: Icons.add_rounded,
                  iconColor: c.text2,
                  title: 'Add your own',
                  subtitle: 'Rent, Gym, Pets: anything k doesn’t have',
                  onTap: () => createCategory(context),
                ),
              for (final e in yours) row(e),
              const SettingsHead('Built in', note: 'Rename or hide'),
              for (final e in builtIn) row(e),
              if (hidden.isNotEmpty) ...[
                const SettingsHead('Hidden'),
                for (final e in hidden) row(e),
              ],
            ],
          );
        },
      ),
    );
  }
}
