import 'package:flutter/material.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../../data/review/review_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/note_chip.dart';
import 'review_editor_screen.dart';

/// Bank messages k could not read (design 03a / 03c).
class ReviewQueueScreen extends StatelessWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return StreamBuilder<List<ReviewItem>>(
      stream: getIt<ReviewService>().watchQueue(),
      builder: (context, snap) {
        final items = snap.data;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text('Review', style: t.headline.copyWith(fontSize: 26)),
              ),
            ),
            if (items == null)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(
                    title: 'Nothing to review',
                    body:
                        'Every bank message so far was read on its own. '
                        "New ones k can't read will wait here.",
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Text(
                    "Bank messages k couldn't read, and payments from senders "
                    "it doesn't know yet. Fix one and k learns it for next "
                    'time.',
                    style: t.body.copyWith(color: c.text2),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _QueueCard(
                    item: items[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ReviewEditorScreen(startRawId: items[i].raw.id),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        );
      },
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.item, required this.onTap});

  final ReviewItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final f = item.guess.fields;
    final credit = f.direction == Direction.credit;
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (f.amountMinor != null)
                    NoteChip(
                      amountMinor: f.amountMinor!,
                      style: credit
                          ? NoteChipStyle.outlined
                          : NoteChipStyle.pending,
                    )
                  else
                    Container(
                      width: 24,
                      height: 12,
                      decoration: BoxDecoration(
                        border: Border.all(color: c.text3, width: 1.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.raw.sender,
                      style: t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (f.amountMinor != null)
                    Text(
                      '${inrRow(f.amountMinor!, plus: credit)}?',
                      style: t.amountRow.copyWith(color: c.text2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.text,
                style: t.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.reason,
                      style: t.label.copyWith(fontSize: 12.5),
                    ),
                  ),
                  Text(
                    '${dayShort(item.raw.receivedAt)}, ${hhmm(item.raw.receivedAt)}',
                    style: t.meta,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
