import 'package:flutter/material.dart';

import '../theme/k_theme.dart';
import 'rosette.dart';

/// Material Symbols Rounded names stored on categories → icons.
IconData categoryIcon(String? name) => switch (name) {
  'restaurant' => Icons.restaurant_rounded,
  'shopping_basket' => Icons.shopping_basket_rounded,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'flight' => Icons.flight_rounded,
  'local_gas_station' => Icons.local_gas_station_rounded,
  'receipt_long' => Icons.receipt_long_rounded,
  'autorenew' => Icons.autorenew_rounded,
  'movie' => Icons.movie_rounded,
  'medical_services' => Icons.medical_services_rounded,
  'school' => Icons.school_rounded,
  'trending_up' => Icons.trending_up_rounded,
  'swap_horiz' => Icons.swap_horiz_rounded,
  'local_atm' => Icons.local_atm_rounded,
  'payments' => Icons.payments_rounded,
  _ => Icons.help_outline_rounded,
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
