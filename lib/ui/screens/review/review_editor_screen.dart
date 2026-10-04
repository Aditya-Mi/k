import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../../data/repositories/ledger_repository.dart';
import '../../../data/review/field_marks.dart';
import '../../../data/review/review_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/note_chip.dart';
import '../../widgets/text_prompt.dart';
import 'learned_overlay.dart';
import 'message_marks.dart';
import 'review_editor_cubit.dart';

/// Fix a message (design 03b): mark fields in the text, confirm values,
/// then Save & learn.
class ReviewEditorScreen extends StatelessWidget {
  const ReviewEditorScreen({super.key, required this.startRawId});

  final String startRawId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ReviewEditorCubit(
      getIt<ReviewService>(),
      getIt<LedgerRepository>(),
      startRawId: startRawId,
    ),
    child: const _EditorView(),
  );
}

class _EditorView extends StatelessWidget {
  const _EditorView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReviewEditorCubit, ReviewEditorState>(
      listenWhen: (a, b) => a.lastResult == null && b.lastResult != null,
      listener: _onResult,
      builder: (context, s) {
        final item = s.item;
        if (item == null) {
          return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
        }
        return _Editor(state: s, item: item);
      },
    );
  }

  Future<void> _onResult(BuildContext context, ReviewEditorState s) async {
    final cubit = context.read<ReviewEditorCubit>();
    final r = s.lastResult;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (r != null) {
      cubit.consumeResult();
      final amount = r.fields.amountMinor ?? 0;
      final who = r.fields.payee == null ? '' : ' to ${r.fields.payee}';
      final more = r.result.cleared == 0
          ? ''
          : ' It also read ${r.result.cleared} more waiting '
                '${r.result.cleared == 1 ? 'message' : 'messages'}.';
      if (r.result.learned) {
        await showLearnedOverlay(
          context,
          amountMinor: amount,
          title: 'Learned this ${r.bank} format',
          body:
              '${inrRow(amount)}$who is saved. ${r.bank} messages shaped like '
              'it will now be read on their own.$more',
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              r.result.learnError == null
                  ? 'Saved'
                  : "Saved. Couldn't learn the format: ${r.result.learnError}",
            ),
          ),
        );
      }
    }
    // Queue emptied: back to the list.
    if (cubit.state.loaded && cubit.state.item == null && nav.canPop()) {
      nav.pop();
    }
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.state, required this.item});

  final ReviewEditorState state;
  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final cubit = context.read<ReviewEditorCubit>();
    final f = cubit.fields();
    final category = state.categories
        .where((x) => x.id == state.categoryId)
        .firstOrNull;
    final isSms = item.raw.channel == Channel.sms;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Review'),
        actions: [
          if (state.queue.length > 1)
            TextButton(
              onPressed: cubit.skip,
              child: Text(
                '${state.index + 1} of ${state.queue.length}',
                style: t.body.copyWith(color: c.text2),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: c.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSms ? Icons.sms_outlined : Icons.mail_outline_rounded,
                      size: 20,
                      color: c.text2,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${item.raw.sender} · ${dayMonth(item.raw.receivedAt)}, '
                        '${hhmm(item.raw.receivedAt)}',
                        style: t.body.copyWith(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(item.reason, style: t.meta.copyWith(color: c.text3)),
                  ],
                ),
                const SizedBox(height: 14),
                MessageMarks(
                  text: item.text,
                  marks: state.marks,
                  onLongPressWord: (s, e) => _markSheet(context, s, e, null),
                  onTapMark: (m) => _markSheet(context, m.start, m.end, m),
                ),
                const SizedBox(height: 14),
                Text(
                  'Long-press a word in the message to mark it as a field.',
                  style: t.meta.copyWith(color: c.text3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FieldRow(
            label: 'Amount',
            onTap: () => _editAmount(context, f.amountMinor),
            value: f.amountMinor == null
                ? Text('Mark or enter', style: t.body.copyWith(color: c.text3))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NoteChip(
                        amountMinor: f.amountMinor!,
                        style: state.direction == Direction.debit
                            ? NoteChipStyle.filled
                            : NoteChipStyle.outlined,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        inr(f.amountMinor!, paise: true),
                        style: t.amountRow.copyWith(fontSize: 18),
                      ),
                    ],
                  ),
          ),
          FieldRow(
            label: 'Direction',
            value: SegmentedButton<Direction>(
              segments: const [
                ButtonSegment(value: Direction.debit, label: Text('Debit')),
                ButtonSegment(value: Direction.credit, label: Text('Credit')),
              ],
              selected: {state.direction},
              onSelectionChanged: (v) => cubit.setDirection(v.single),
            ),
          ),
          FieldRow(
            label: 'Account',
            onTap: () => _pickAccount(context),
            value: Text(
              cubit.accountLabel(),
              style: t.body,
              textAlign: TextAlign.right,
            ),
          ),
          FieldRow(
            label: 'Payee',
            onTap: () => _editText(context, 'Payee', f.payee, cubit.setPayee),
            value: Text(
              f.payee ?? 'None',
              style: t.body.copyWith(color: f.payee == null ? c.text3 : c.text),
              textAlign: TextAlign.right,
            ),
          ),
          FieldRow(
            label: 'Reference',
            onTap: () => _editText(context, 'Reference', f.ref, cubit.setRef),
            value: Text(
              f.ref ?? 'None',
              style: t.body.copyWith(color: f.ref == null ? c.text3 : c.text),
            ),
          ),
          FieldRow(
            label: 'Date',
            onTap: () =>
                _pickDate(context, f.occurredAt ?? item.raw.receivedAt),
            value: Text(
              fullStamp(f.occurredAt ?? item.raw.receivedAt),
              style: t.body,
            ),
          ),
          FieldRow(
            label: 'Category',
            value: OutlinedButton(
              onPressed: () => _pickCategory(context),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.only(left: 16, right: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category != null) ...[
                    Icon(categoryIcon(category.icon), size: 18, color: c.text2),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    category?.name ?? 'Choose',
                    style: t.body.copyWith(
                      color: category == null ? c.text2 : c.text,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, color: c.text2),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Learn this format', style: t.title),
                    const SizedBox(height: 4),
                    Text(
                      'Next time ${cubit.bankShort()} sends a message shaped '
                      'like this, k reads it on its own.',
                      style: t.body.copyWith(color: c.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(value: state.learn, onChanged: cubit.setLearn),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.outline)),
          ),
          child: Row(
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: state.saving
                    ? null
                    : () async {
                        final nav = Navigator.of(context);
                        await cubit.notATransaction();
                        if (cubit.state.item == null && nav.canPop()) {
                          nav.pop();
                        }
                      },
                child: const Text('Not a transaction'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.saving || f.amountMinor == null
                      ? null
                      : () => _save(context),
                  icon: state.saving
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.onInk,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(state.learn ? 'Save & learn' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    try {
      await context.read<ReviewEditorCubit>().save();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  /// Long-press sheet: grow/shrink the selection word by word, then pick
  /// which field it is (or clear an existing mark).
  Future<void> _markSheet(
    BuildContext context,
    int start,
    int end,
    FieldMark? existing,
  ) async {
    final cubit = context.read<ReviewEditorCubit>();
    final text = item.text;
    final words = RegExp(r'[^\s/]+').allMatches(text).toList();
    var first = words.indexWhere((w) => w.end > start);
    var last = words.lastIndexWhere((w) => w.start < end);
    if (first < 0 || last < first) return;

    final picked = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final t = context.kt;
          final c = context.k;
          final selection = text.substring(words[first].start, words[last].end);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mark as', style: t.title),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Start one word earlier',
                        onPressed: first > 0
                            ? () => setSheet(() => first--)
                            : null,
                        icon: const Icon(Icons.keyboard_arrow_left_rounded),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface3,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            selection,
                            style: t.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'One word fewer',
                        onPressed: last > first
                            ? () => setSheet(() => last--)
                            : null,
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      IconButton(
                        tooltip: 'One word more',
                        onPressed: last < words.length - 1
                            ? () => setSheet(() => last++)
                            : null,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final field in MarkField.values)
                        ActionChip(
                          label: Text(_fieldName(field)),
                          onPressed: () => Navigator.pop(context, (
                            field,
                            words[first].start,
                            words[last].end,
                          )),
                        ),
                    ],
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, 'clear'),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Remove mark'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == 'clear' && existing != null) {
      cubit.unmark(existing);
    } else if (picked case (final MarkField field, final int s, final int e)) {
      if (!cubit.mark(field, s, e) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("That doesn't look like ${_fieldArticle(field)}"),
          ),
        );
      }
    }
  }

  String _fieldName(MarkField f) => switch (f) {
    MarkField.account => 'Account no.',
    MarkField.direction => 'Debit/credit word',
    MarkField.amount => 'Amount',
    MarkField.payee => 'Payee',
    MarkField.ref => 'Reference',
    MarkField.date => 'Date',
    MarkField.balance => 'Balance',
  };

  String _fieldArticle(MarkField f) => switch (f) {
    MarkField.account => 'an account number (4 digits)',
    MarkField.amount => 'an amount',
    MarkField.balance => 'a balance',
    MarkField.ref => 'a reference',
    MarkField.date => 'a date',
    _ => 'that field',
  };

  Future<void> _editAmount(BuildContext context, int? current) async {
    final v = await _prompt(
      context,
      'Amount',
      current == null ? '' : (current / 100).toStringAsFixed(2),
      numeric: true,
    );
    final minor = v == null ? null : parseAmountMinor(v);
    if (minor != null && context.mounted) {
      context.read<ReviewEditorCubit>().setAmount(minor);
    }
  }

  Future<void> _editText(
    BuildContext context,
    String title,
    String? current,
    void Function(String) apply,
  ) async {
    final v = await _prompt(context, title, current ?? '');
    if (v != null && v.trim().isNotEmpty) apply(v.trim());
  }

  Future<String?> _prompt(
    BuildContext context,
    String title,
    String initial, {
    bool numeric = false,
  }) async {
    return promptText(
      context,
      title: title,
      initial: initial,
      action: 'Done',
      numeric: numeric,
    );
  }

  Future<void> _pickDate(BuildContext context, DateTime current) async {
    final cubit = context.read<ReviewEditorCubit>();
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 3),
      lastDate: DateTime.now(),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    final t = time ?? TimeOfDay.fromDateTime(current);
    cubit.setDate(DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  Future<void> _pickAccount(BuildContext context) async {
    final cubit = context.read<ReviewEditorCubit>();
    final accounts = cubit.bankAccounts();
    final picked = await showModalBottomSheet<(String?,)>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.short_text_rounded),
              title: const Text('From the message'),
              subtitle: const Text('Use the account number marked above'),
              onTap: () => Navigator.pop(context, (null,)),
            ),
            for (final a in accounts)
              ListTile(
                title: Text(a.long),
                trailing: a.id == state.accountId
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, (a.id,)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) cubit.setAccount(picked.$1);
  }

  Future<void> _pickCategory(BuildContext context) async {
    final cubit = context.read<ReviewEditorCubit>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final cat in state.categories)
                ListTile(
                  leading: Icon(categoryIcon(cat.icon), color: context.k.text2),
                  title: Text(cat.name),
                  trailing: cat.id == state.categoryId
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, cat.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) cubit.setCategory(picked);
  }
}
