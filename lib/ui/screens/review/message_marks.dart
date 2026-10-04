import 'package:flutter/material.dart';
import 'package:txn_parser/txn_parser.dart' show parseAmountMinor;

import '../../../data/review/field_marks.dart';
import '../../theme/k_theme.dart';

/// The message, tokenised: plain words, and marked field values on a
/// surface-3 mark with a 2dp underline and a letterspaced caption above
/// (DESIGN.md "Message Marks"). Only the amount mark takes its band ink.
class MessageMarks extends StatelessWidget {
  const MessageMarks({
    super.key,
    required this.text,
    required this.marks,
    required this.onLongPressWord,
    required this.onTapMark,
  });

  final String text;
  final List<FieldMark> marks;

  /// Character range of the pressed plain word.
  final void Function(int start, int end) onLongPressWord;
  final void Function(FieldMark mark) onTapMark;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    final style = t.body.copyWith(fontSize: 17, height: 1.3);
    final children = <Widget>[];

    void plain(int from, int to) {
      for (final m in RegExp(r'\S+').allMatches(text.substring(from, to))) {
        final s = from + m.start;
        final e = from + m.end;
        children.add(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => onLongPressWord(s, e),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                text.substring(s, e),
                style: style.copyWith(color: c.text2),
              ),
            ),
          ),
        );
      }
    }

    var cursor = 0;
    for (final m in marks) {
      if (m.start < cursor) continue;
      plain(cursor, m.start);
      children.add(
        _Mark(
          mark: m,
          value: m.valueIn(text),
          style: style,
          onTap: () => onTapMark(m),
        ),
      );
      cursor = m.end;
    }
    plain(cursor, text.length);

    return Wrap(
      spacing: 5,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: children,
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({
    required this.mark,
    required this.value,
    required this.style,
    required this.onTap,
  });

  final FieldMark mark;
  final String value;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final minor = mark.field == MarkField.amount
        ? parseAmountMinor(value)
        : null;
    final accent = minor == null ? c.text3 : c.ink(Bands.of(minor));
    return Semantics(
      button: true,
      label: '${mark.field.caption.toLowerCase()}: $value',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 2),
              child: Text(
                mark.field.caption,
                style: context.kt.label.copyWith(
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                  color: minor == null ? c.text3 : accent,
                ),
              ),
            ),
            // Radius + one-sided border can't share a BoxDecoration: clip.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: c.surface3,
                  border: Border(bottom: BorderSide(color: accent, width: 2)),
                ),
                child: Text(
                  value,
                  style: style.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
