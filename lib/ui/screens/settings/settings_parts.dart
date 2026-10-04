import 'package:flutter/material.dart';

import '../../theme/k_theme.dart';

/// Section label in the design 06 style.
class SettingsHead extends StatelessWidget {
  const SettingsHead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(
      text,
      style: context.kt.meta.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
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
                    style: t.body.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: t.meta.copyWith(
                      fontSize: 13,
                      height: 1.35,
                      color: subtitleColor,
                    ),
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
