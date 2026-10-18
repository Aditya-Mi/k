import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:txn_parser/txn_parser.dart' show noMoneyMovedNote;

import '../../../data/db/app_database.dart' show RawMessage;
import '../../../data/ingest/raw_notes.dart';
import '../../../data/review/review_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/k_sheet.dart';

/// Bank messages k skipped on its own (design 06m), grouped by day. Tap one
/// to read it whole and send it to Review (06n). The owner's own "Not a
/// transaction" picks stay out.
class SkippedScreen extends StatelessWidget {
  const SkippedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Skipped messages'),
      ),
      body: StreamBuilder<List<RawMessage>>(
        stream: getIt<ReviewService>().watchSkipped(),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) return const SizedBox.shrink();
          if (list.isEmpty) {
            return const Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  title: 'Nothing skipped',
                  body:
                      'Bank messages where no money moved, like OTPs and '
                      'offers, appear here.',
                ),
              ),
            );
          }
          final now = DateTime.now();
          final items = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
              child: Text(
                'Bank messages k didn\'t log because no money moved. Your '
                'own "Not a transaction" picks stay out of this list.',
                style: t.body.copyWith(color: c.text2, height: 1.4),
              ),
            ),
          ];
          DateTime? day;
          for (final m in list) {
            final d = dateOnly(m.receivedAt);
            if (d != day) {
              day = d;
              items.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                  child: Text(
                    dayLabel(d, now),
                    style: t.meta.copyWith(
                      color: c.text2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }
            items.add(_Row(message: m));
          }
          items.add(
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Tap a message to read it or send it to Review.',
                style: t.meta.copyWith(color: c.text2),
              ),
            ),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: items,
          );
        },
      ),
    );
  }
}

/// Why k skipped a message, from its parse note.
(String, IconData) skipReason(String? note) => switch (note) {
  'otp' => ('One-time password', Symbols.password),
  'promotional' => ('Offer', Symbols.campaign),
  'declined' => ('Declined payment', Symbols.do_not_disturb_on),
  'ignore template' => ('Matches a format k skips', Symbols.school),
  noMoneyMovedNote => ('No money moved', Symbols.block),
  noAmountNote => ('Email without an amount', Symbols.mail),
  _ => ('Not a payment', Symbols.block),
};

String _text(RawMessage m) =>
    [?m.subject, m.body].join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

class _Row extends StatelessWidget {
  const _Row({required this.message});

  final RawMessage message;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    final (reason, icon) = skipReason(message.parseNote);
    return InkWell(
      onTap: () => _open(context, message),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.outline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    message.sender,
                    style: t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  hhmm(message.receivedAt),
                  style: t.meta.copyWith(color: c.text3),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _text(message),
              style: t.meta.copyWith(color: c.text2, height: 1.35),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(icon, size: 16, color: c.text3),
                const SizedBox(width: 6),
                Text(reason, style: t.meta.copyWith(color: c.text3)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, RawMessage m) async {
  final send = await showKDialog<bool>(
    context: context,
    builder: (context) {
      final t = context.kt;
      final c = context.k;
      final (reason, icon) = skipReason(m.parseNote);
      final now = DateTime.now();
      final when = dateOnly(m.receivedAt) == dateOnly(now)
          ? 'Today, ${hhmm(m.receivedAt)}'
          : fullStamp(m.receivedAt);
      return KDialog(
        title: Text(m.sender),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: c.text2),
                const SizedBox(width: 6),
                Flexible(child: Text('$reason · $when')),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _text(m),
                style: t.body.copyWith(color: c.text, height: 1.45),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'If money did move, send it to Review and k will ask you '
              'what it was.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send to Review'),
          ),
        ],
      );
    },
  );
  if (send != true) return;
  await getIt<ReviewService>().sendToReview(m.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Sent to Review')));
}
