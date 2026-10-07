import 'package:flutter/material.dart';

import '../theme/k_theme.dart';

/// Every sheet and confirmation in k (DESIGN.md "Floating Note"): a 24dp
/// surface-2 card floating 12dp off the screen edges, rising from the
/// bottom. Pop it with `Navigator.pop(context, value)` like any route.
Future<T?> showKSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool avoidKeyboard = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: (context) =>
      _FloatingNote(avoidKeyboard: avoidKeyboard, child: builder(context)),
);

/// A confirmation or small form as a floating note at the bottom, in place
/// of a centred dialog. [builder] usually returns a [KDialog].
Future<T?> showKDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showKSheet<T>(
  context: context,
  builder: builder,
  isScrollControlled: true,
  isDismissible: barrierDismissible,
  enableDrag: barrierDismissible,
  avoidKeyboard: true,
);

class _FloatingNote extends StatelessWidget {
  const _FloatingNote({required this.avoidKeyboard, required this.child});

  final bool avoidKeyboard;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = avoidKeyboard ? mq.viewInsets.bottom : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        mq.padding.top + 12,
        12,
        12 + (keyboard > 0 ? keyboard : mq.padding.bottom),
      ),
      child: Material(
        color: context.k.surface2,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          removeTop: true,
          child: Padding(padding: const EdgeInsets.only(top: 16), child: child),
        ),
      ),
    );
  }
}

/// The counterfoil tear: a dashed hairline in text-3 between what a note
/// says and what you can do with it.
class TearLine extends StatelessWidget {
  const TearLine({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.fromHeight(1),
    painter: _TearPainter(context.k.text3),
  );
}

class _TearPainter extends CustomPainter {
  _TearPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, 1), p);
    }
  }

  @override
  bool shouldRepaint(_TearPainter old) => old.color != color;
}

/// AlertDialog's shape for a floating note: optional icon, title, content,
/// a tear line, then [actions] stacked full width. Pass actions in the
/// usual order (dismiss first, main action last); the main action goes on
/// top, filled, in alert colour when [destructive].
class KDialog extends StatelessWidget {
  const KDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
    this.destructive = false,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final theme = Theme.of(context);
    final fill = destructive ? c.alert : c.text;
    final label = theme.filledButtonTheme.style?.textStyle?.resolve({});
    final primary = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? c.surface3 : fill,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? c.text3 : c.onInk,
      ),
      textStyle: WidgetStatePropertyAll(label),
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    );
    final secondary = TextButton.styleFrom(
      foregroundColor: c.text,
      minimumSize: const Size.fromHeight(48),
      shape: const StadiumBorder(),
      textStyle: label,
    );
    final ordered = actions.reversed.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    IconTheme.merge(
                      data: IconThemeData(color: c.text2, size: 24),
                      child: icon!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (title != null)
                    DefaultTextStyle(
                      style: t.headline.copyWith(color: c.text),
                      child: title!,
                    ),
                  if (content != null) ...[
                    const SizedBox(height: 8),
                    DefaultTextStyle(
                      style: t.body.copyWith(color: c.text2, height: 1.4),
                      child: content!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (ordered.isNotEmpty) ...[
            const SizedBox(height: 20),
            const TearLine(),
            const SizedBox(height: 16),
            for (final (i, a) in ordered.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                child: Theme(
                  data: theme.copyWith(
                    textButtonTheme: TextButtonThemeData(
                      style: i == 0 ? primary : secondary,
                    ),
                    filledButtonTheme: FilledButtonThemeData(style: primary),
                  ),
                  child: a,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
