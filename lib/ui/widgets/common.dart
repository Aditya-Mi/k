import 'package:flutter/material.dart';

import '../../data/db/app_database.dart' show Category;
import '../theme/k_theme.dart';
import 'rosette.dart';

/// Icons a category can use (design 06j), by the Material Symbols name
/// stored on the row. Built-ins use the first ones too.
const categoryIcons = <String, IconData>{
  'home': Icons.home_rounded,
  'restaurant': Icons.restaurant_rounded,
  'shopping_basket': Icons.shopping_basket_rounded,
  'shopping_bag': Icons.shopping_bag_outlined,
  'flight': Icons.flight_rounded,
  'local_gas_station': Icons.local_gas_station_rounded,
  'directions_car': Icons.directions_car_rounded,
  'local_taxi': Icons.local_taxi_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'call': Icons.call_rounded,
  'wifi': Icons.wifi_rounded,
  'autorenew': Icons.autorenew_rounded,
  'movie': Icons.movie_rounded,
  'sports_esports': Icons.sports_esports_rounded,
  'medical_services': Icons.medical_services_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'spa': Icons.spa_rounded,
  'school': Icons.school_rounded,
  'child_care': Icons.child_care_rounded,
  'pets': Icons.pets_rounded,
  'redeem': Icons.redeem_rounded,
  'volunteer_activism': Icons.volunteer_activism_rounded,
  'account_balance': Icons.account_balance_rounded,
  'savings': Icons.savings_rounded,
  'trending_up': Icons.trending_up_rounded,
  'local_cafe': Icons.local_cafe_rounded,
  'checkroom': Icons.checkroom_rounded,
  'build': Icons.build_rounded,
  'celebration': Icons.celebration_rounded,
  'payments': Icons.payments_rounded,
};

/// Material Symbols Rounded names stored on categories → icons.
IconData categoryIcon(String? name) => switch (name) {
  'swap_horiz' => Icons.swap_horiz_rounded,
  'local_atm' => Icons.local_atm_rounded,
  _ => categoryIcons[name] ?? Icons.help_outline_rounded,
};

/// 32dp outlined chip with a trailing dropdown arrow.
class KFilterChip extends StatelessWidget {
  const KFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Narrowed from its default: steps up to surface-3 (never an ink).
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Material(
      color: active ? c.surface3 : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 14, right: 8),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: context.kt.body),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down_rounded, size: 20, color: c.text2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined neutral banner with an action — review queue, SMS access off.
/// Never alert-coloured (The Calm Count Rule).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.text2),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: t.body)),
              TextButton(onPressed: onTap, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Day group label with the day's money-out total on the right.
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.dayHeader)),
          if (trailing != null) Text(trailing!, style: t.meta),
        ],
      ),
    );
  }
}

/// Label-left, value-right detail row over a hairline.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.outline)),
        ),
        child: Row(
          children: [
            Text(label, style: context.kt.body.copyWith(color: c.text2)),
            const SizedBox(width: 16),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
          ],
        ),
      ),
    );
  }
}

/// House rosette in text-2 instead of a generic icon.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.body, this.action});

  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Rosette(size: 132, color: c.text2, strokeWidth: 0.6),
          const SizedBox(height: 24),
          Text(title, style: t.title, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              style: t.body.copyWith(color: c.text2),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// Category with its icon on a surface-2 button; tap to change.
class CategoryButton extends StatelessWidget {
  const CategoryButton({
    super.key,
    required this.category,
    required this.onTap,
  });

  final Category? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(categoryIcon(category?.icon), size: 20, color: c.text2),
              const SizedBox(width: 10),
              Text(
                category?.name ?? 'Uncategorized',
                style: context.kt.body.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 10),
              Icon(Icons.edit_outlined, size: 16, color: c.text2),
            ],
          ),
        ),
      ),
    );
  }
}
