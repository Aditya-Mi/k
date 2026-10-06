import 'package:flutter/material.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../../data/review/review_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../motion.dart';
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
                child: Text('Review', style: t.headline),
              ),
            ),
            if (items != null && items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(
                    title: 'Nothing to review',
                    body: "Messages k can't read will wait here.",
                  ),
                ),
              ),
            if (items != null && items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    '${items.length} to review',
                    style: t.body.copyWith(color: c.text2),
                  ),
                ),
              ),
            // Always mounted, so a card coming back on Undo slides in even
            // when the queue was empty.
            if (items != null)
              SliverPadding(
                key: const ValueKey('queue'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: _AnimatedQueue(items: items),
              ),
          ],
        );
      },
    );
  }
}

/// The queue as a list whose cards collapse out when read (saved, skipped
/// as not a transaction) and slide back in on Undo (DESIGN.md Motion).
class _AnimatedQueue extends StatefulWidget {
  const _AnimatedQueue({required this.items});

  final List<ReviewItem> items;

  @override
  State<_AnimatedQueue> createState() => _AnimatedQueueState();
}

class _AnimatedQueueState extends State<_AnimatedQueue> {
  final _list = GlobalKey<SliverAnimatedListState>();
  late final List<ReviewItem> _shown = [...widget.items];

  @override
  void didUpdateWidget(_AnimatedQueue old) {
    super.didUpdateWidget(old);
    final next = widget.items;
    final list = _list.currentState;
    final duration = Motion.of(context, Motion.medium);
    final keep = {for (final i in next) i.raw.id};
    // Removals, back to front so indexes stay valid.
    for (var i = _shown.length - 1; i >= 0; i--) {
      if (keep.contains(_shown[i].raw.id)) continue;
      final gone = _shown.removeAt(i);
      list?.removeItem(
        i,
        (context, a) => _transition(a, _card(gone, interactive: false)),
        duration: duration,
      );
    }
    // Insertions in the new order; the rest refresh in place.
    for (var i = 0; i < next.length; i++) {
      if (i < _shown.length && _shown[i].raw.id == next[i].raw.id) {
        _shown[i] = next[i];
        continue;
      }
      final at = _shown.indexWhere((x) => x.raw.id == next[i].raw.id);
      if (at >= 0) {
        // Moved: no animation, just put it in place.
        _shown.removeAt(at);
        _shown.insert(i, next[i]);
        continue;
      }
      _shown.insert(i, next[i]);
      list?.insertItem(i, duration: duration);
    }
  }

  static Widget _transition(Animation<double> a, Widget child) {
    final curved = CurvedAnimation(
      parent: a,
      curve: Motion.enter,
      reverseCurve: Motion.exit,
    );
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(-0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }

  Widget _card(ReviewItem item, {bool interactive = true}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: IgnorePointer(
      ignoring: !interactive,
      child: _QueueCard(
        item: item,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReviewEditorScreen(startRawId: item.raw.id),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SliverAnimatedList(
    key: _list,
    initialItemCount: _shown.length,
    itemBuilder: (context, i, a) => _transition(a, _card(_shown[i])),
  );
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
                    const NoteChip(
                      amountMinor: 0,
                      style: NoteChipStyle.unknown,
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
                  Expanded(child: Text(item.reason, style: t.label)),
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
