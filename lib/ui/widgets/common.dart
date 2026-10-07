import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/db/app_database.dart' show Category;
import '../theme/k_theme.dart';
import 'rosette.dart';

/// Icons a category can use (design 06j), grouped for the picker, by the
/// Material Symbols name stored on the row. Never rename a key: rows store it.
const categoryIconGroups = <(String, Map<String, IconData>)>[
  (
    'Home & bills',
    {
      'home': Symbols.home,
      'cottage': Symbols.cottage,
      'key': Symbols.key,
      'bolt': Symbols.bolt,
      'water_drop': Symbols.water_drop,
      'propane_tank': Symbols.propane_tank,
      'wifi': Symbols.wifi,
      'call': Symbols.call,
      'smartphone': Symbols.smartphone,
      'tv': Symbols.tv,
      'cleaning_services': Symbols.cleaning_services,
      'chair': Symbols.chair,
      'receipt_long': Symbols.receipt_long,
      'autorenew': Symbols.autorenew,
      'subscriptions': Symbols.subscriptions,
    },
  ),
  (
    'Food',
    {
      'restaurant': Symbols.restaurant,
      'local_cafe': Symbols.local_cafe,
      'lunch_dining': Symbols.lunch_dining,
      'local_pizza': Symbols.local_pizza,
      'ramen_dining': Symbols.ramen_dining,
      'bakery_dining': Symbols.bakery_dining,
      'icecream': Symbols.icecream,
      'delivery_dining': Symbols.delivery_dining,
      'shopping_basket': Symbols.shopping_basket,
      'nutrition': Symbols.nutrition,
      'liquor': Symbols.liquor,
    },
  ),
  (
    'Getting around',
    {
      'directions_car': Symbols.directions_car,
      'two_wheeler': Symbols.two_wheeler,
      'local_taxi': Symbols.local_taxi,
      'electric_rickshaw': Symbols.electric_rickshaw,
      'directions_bus': Symbols.directions_bus,
      'train': Symbols.train,
      'subway': Symbols.subway,
      'flight': Symbols.flight,
      'local_gas_station': Symbols.local_gas_station,
      'ev_station': Symbols.ev_station,
      'local_parking': Symbols.local_parking,
      'toll': Symbols.toll,
      'pedal_bike': Symbols.pedal_bike,
    },
  ),
  (
    'Shopping',
    {
      'shopping_bag': Symbols.shopping_bag,
      'shopping_cart': Symbols.shopping_cart,
      'local_mall': Symbols.local_mall,
      'checkroom': Symbols.checkroom,
      'diamond': Symbols.diamond,
      'devices': Symbols.devices,
      'laptop_mac': Symbols.laptop_mac,
      'headphones': Symbols.headphones,
      'menu_book': Symbols.menu_book,
      'local_florist': Symbols.local_florist,
      'redeem': Symbols.redeem,
    },
  ),
  (
    'Health & care',
    {
      'medical_services': Symbols.medical_services,
      'local_pharmacy': Symbols.local_pharmacy,
      'medication': Symbols.medication,
      'dentistry': Symbols.dentistry,
      'health_and_safety': Symbols.health_and_safety,
      'fitness_center': Symbols.fitness_center,
      'spa': Symbols.spa,
      'content_cut': Symbols.content_cut,
    },
  ),
  (
    'Fun & travel',
    {
      'movie': Symbols.movie,
      'theater_comedy': Symbols.theater_comedy,
      'music_note': Symbols.music_note,
      'sports_esports': Symbols.sports_esports,
      'sports_cricket': Symbols.sports_cricket,
      'sports_soccer': Symbols.sports_soccer,
      'stadium': Symbols.stadium,
      'celebration': Symbols.celebration,
      'cake': Symbols.cake,
      'luggage': Symbols.luggage,
      'hotel': Symbols.hotel,
      'beach_access': Symbols.beach_access,
      'photo_camera': Symbols.photo_camera,
    },
  ),
  (
    'People',
    {
      'child_care': Symbols.child_care,
      'school': Symbols.school,
      'family_restroom': Symbols.family_restroom,
      'elderly': Symbols.elderly,
      'pets': Symbols.pets,
      'favorite': Symbols.favorite,
      'volunteer_activism': Symbols.volunteer_activism,
      'temple_hindu': Symbols.temple_hindu,
      'mosque': Symbols.mosque,
      'church': Symbols.church,
    },
  ),
  (
    'Money & work',
    {
      'payments': Symbols.payments,
      'account_balance': Symbols.account_balance,
      'savings': Symbols.savings,
      'trending_up': Symbols.trending_up,
      'credit_card': Symbols.credit_card,
      'currency_rupee': Symbols.currency_rupee,
      'percent': Symbols.percent,
      'request_quote': Symbols.request_quote,
      'receipt': Symbols.receipt,
      'shield': Symbols.shield,
      'work': Symbols.work,
      'storefront': Symbols.storefront,
    },
  ),
  (
    'Other',
    {
      'build': Symbols.build,
      'handyman': Symbols.handyman,
      'local_laundry_service': Symbols.local_laundry_service,
      'local_shipping': Symbols.local_shipping,
      'print': Symbols.print,
      'cloud': Symbols.cloud,
      'sell': Symbols.sell,
      'label': Symbols.label,
    },
  ),
];

/// Every pickable icon, in picker order.
final categoryIcons = <String, IconData>{
  for (final (_, icons) in categoryIconGroups) ...icons,
};

/// Material Symbols names stored on categories → icons.
IconData categoryIcon(String? name) => switch (name) {
  'swap_horiz' => Symbols.swap_horiz,
  'local_atm' => Symbols.local_atm,
  _ => categoryIcons[name] ?? Symbols.help,
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
              Icon(Symbols.arrow_drop_down, size: 20, color: c.text2),
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
    this.detail,
    this.problem = false,
  });

  final IconData icon;
  final String text;

  /// Second line in meta (design 01c).
  final String? detail;
  final String action;
  final VoidCallback onTap;

  /// Something stopped working (SMS off, inbox failing): the icon takes the
  /// alert colour, as in Settings (06d). The review banner stays neutral.
  final bool problem;

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
              Icon(icon, size: 20, color: problem ? c.alert : c.text2),
              const SizedBox(width: 14),
              Expanded(
                child: detail == null
                    ? Text(text, style: t.body)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text,
                            style: t.body.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(detail!, style: t.meta),
                        ],
                      ),
              ),
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
              Icon(Symbols.edit, size: 16, color: c.text2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined 8dp select: label (or "Choose") and a dropdown arrow.
class SelectButton extends StatelessWidget {
  const SelectButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.only(left: 16, right: 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: c.text2),
            const SizedBox(width: 8),
          ],
          Text(
            label ?? 'Choose',
            style: t.body.copyWith(color: label == null ? c.text2 : c.text),
          ),
          Icon(Symbols.arrow_drop_down, color: c.text2),
        ],
      ),
    );
  }
}
