import 'package:flutter/material.dart';

import '../../theme/k_theme.dart';

/// Section label in the design 06 style.
class SettingsHead extends StatelessWidget {
  const SettingsHead(this.text, {super.key, this.note});

  final String text;

  /// Right-aligned aside ("Added from messages").
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: context.kt.meta.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (note != null) Text(note!, style: context.kt.meta),
      ],
    ),
  );
}

/// Trailing chevron for items that open something.
class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.chevron_right_rounded, size: 20, color: context.k.text3);
}

/// Icon, title over subtitle, trailing control (design 06 items).
class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.subtitleColor,
  });

  final Color? iconColor;
  final Color? subtitleColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor ?? c.text2),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.body.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: t.meta.copyWith(height: 1.35, color: subtitleColor),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          ],
        ),
      ),
    );
  }
}
