import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../widgets/k_sheet.dart';

import '../categories/category_edit_screen.dart';
import '../../../data/repositories/bank_repository.dart';
import '../../widgets/bank_picker.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../data/review/field_marks.dart';
import '../../../data/review/review_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../motion.dart';
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
  const ReviewEditorScreen({
    super.key,
    required this.startRawId,
    this.editTemplateId,
  });

  final String startRawId;

  /// Edit this learned format on its sample ([startRawId]) instead.
  final String? editTemplateId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ReviewEditorCubit(
      getIt<ReviewService>(),
      getIt<LedgerRepository>(),
      getIt<BankRepository>(),
      startRawId: startRawId,
      editTemplateId: editTemplateId,
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
          : ' ${r.result.cleared} more waiting '
                '${r.result.cleared == 1 ? 'message' : 'messages'} read too.';
      final autopay = r.fields.dueDate != null;
      if (cubit.editing) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              r.result.learned
                  ? 'Format updated'
                  : "Format not changed: ${r.result.learnError}",
            ),
          ),
        );
      } else if (r.result.learned) {
        await showLearnedOverlay(
          context,
          amountMinor: amount,
          title: autopay
              ? 'Learned this ${r.bank} AutoPay format'
              : 'Learned this ${r.bank} format',
          body: autopay
              ? '${inrRow(amount)}$who is in Upcoming for '
                    '${dayShort(r.fields.dueDate!)}.$more'
              : '${inrRow(amount)}$who is saved.$more',
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
    final mandate = state.isMandate;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Symbols.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(cubit.editing ? 'Edit format' : 'Review'),
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
      // Save or skip slides the next message in (DESIGN.md Motion).
      body: SharedAxisSwitcher(
        child: ListView(
          key: ValueKey(item.raw.id),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 8),
            if (item.unknownSender) ...[
              Text("A sender k doesn't know", style: t.title),
              const SizedBox(height: 4),
              Text(
                "If it's from your bank, pick the bank.",
                style: t.body.copyWith(color: c.text2),
              ),
              const SizedBox(height: 16),
            ],
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
                        isSms ? Symbols.sms : Symbols.mail,
                        size: 20,
                        color: c.text2,
                      ),
                      const SizedBox(width: 12),
                      // Reason on its own line, so the time never truncates.
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.raw.sender} · '
                              '${dayMonth(item.raw.receivedAt)}, '
                              '${hhmm(item.raw.receivedAt)}',
                              style: t.body.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.reason,
                              style: t.meta.copyWith(color: c.text3),
                            ),
                          ],
                        ),
                      ),
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
            if (item.unknownSender)
              FieldRow(
                label: 'Bank',
                value: SelectButton(
                  label: cubit.bankLabel(),
                  onPressed: () => _pickBank(context),
                ),
              ),
            FieldRow(
              label: 'Message',
              value: SegmentedButton<TemplateKind>(
                segments: const [
                  ButtonSegment(
                    value: TemplateKind.transaction,
                    label: Text('Payment'),
                  ),
                  ButtonSegment(
                    value: TemplateKind.mandate,
                    label: Text('AutoPay due'),
                  ),
                ],
                selected: {state.kind},
                onSelectionChanged: (v) => cubit.setKind(v.single),
              ),
            ),
            FieldRow(
              label: 'Amount',
              onTap: () => _editAmount(context, f.amountMinor),
              value: f.amountMinor == null
                  ? Text(
                      'Mark or enter',
                      style: t.body.copyWith(color: c.text3),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NoteChip(
                          amountMinor: f.amountMinor!,
                          style: mandate
                              ? NoteChipStyle.pending
                              : state.direction == Direction.debit
                              ? NoteChipStyle.filled
                              : NoteChipStyle.outlined,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          inr(f.amountMinor!, paise: true),
                          style: t.amountRow,
                        ),
                      ],
                    ),
            ),
            if (!mandate) ...[
              FieldRow(
                label: 'Direction',
                value: SegmentedButton<Direction>(
                  segments: const [
                    ButtonSegment(value: Direction.debit, label: Text('Debit')),
                    ButtonSegment(
                      value: Direction.credit,
                      label: Text('Credit'),
                    ),
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
            ],
            FieldRow(
              label: 'Payee',
              onTap: () => _editText(context, 'Payee', f.payee, cubit.setPayee),
              value: Text(
                f.payee ?? 'None',
                style: t.body.copyWith(
                  color: f.payee == null ? c.text3 : c.text,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            if (mandate)
              FieldRow(
                label: 'Due on',
                onTap: () => _pickDueDate(context, f.dueDate),
                value: Text(
                  f.dueDate == null ? 'Mark or pick' : dayShortYear(f.dueDate!),
                  style: t.body.copyWith(
                    color: f.dueDate == null ? c.text3 : c.text,
                  ),
                ),
              )
            else ...[
              FieldRow(
                label: 'Reference',
                onTap: () =>
                    _editText(context, 'Reference', f.ref, cubit.setRef),
                value: Text(
                  f.ref ?? 'None',
                  style: t.body.copyWith(
                    color: f.ref == null ? c.text3 : c.text,
                  ),
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
              if (!cubit.editing)
                FieldRow(
                  label: 'Category',
                  value: SelectButton(
                    label: category?.name,
                    icon: category == null ? null : categoryIcon(category.icon),
                    onPressed: () => _pickCategory(context),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            if (cubit.editing)
              Text(
                'Saving replaces this format. Payments it already logged '
                'stay as they are.',
                style: t.body.copyWith(color: c.text2),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Learn this format', style: t.title),
                        const SizedBox(height: 4),
                        Text(
                          item.unknownSender
                              ? 'k reads ${item.raw.sender} as '
                                    '${cubit.bankLabel() ?? 'that bank'} from now '
                                    'on.'
                              : mandate
                              ? 'Similar AutoPay alerts go to Upcoming on their own.'
                              : 'Similar messages are read on their own.',
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
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.outline)),
          ),
          child: Row(
            children: [
              if (!cubit.editing) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: state.saving
                      ? null
                      : () => item.unknownSender
                            ? _notABank(context)
                            : _notATransaction(context),
                  child: Text(
                    item.unknownSender ? 'Not a bank' : 'Not a transaction',
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      state.saving ||
                          f.amountMinor == null ||
                          (item.unknownSender && state.bank == null) ||
                          (mandate && f.dueDate == null)
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
                      : const Icon(Symbols.check),
                  label: Text(
                    cubit.editing
                        ? 'Save format'
                        : state.learn
                        ? 'Save & learn'
                        : 'Save',
                  ),
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

  /// Long-press sheet: grow/shrink the selection word by word, or drag the
  /// handles to mark part of it ("XX001111" → "1111"), then pick which
  /// field it is (or clear an existing mark). Untouched selections are
  /// trimmed to the field; a dragged one is kept as chosen.
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

    final part = TextEditingController();
    void resetPart() {
      part.value = TextEditingValue(
        text: text.substring(words[first].start, words[last].end),
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: words[last].end - words[first].start,
        ),
      );
    }

    resetPart();
    // Tapping a mark starts from exactly what it holds.
    if (existing != null) {
      final base = words[first].start;
      part.selection = TextSelection(
        baseOffset: existing.start - base,
        extentOffset: existing.end - base,
      );
    }
    final picked = await showKSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final t = context.kt;
          final c = context.k;
          void words2(VoidCallback change) => setSheet(() {
            change();
            resetPart();
          });
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
                            ? () => words2(() => first--)
                            : null,
                        icon: const Icon(Symbols.keyboard_arrow_left),
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
                          // Read-only: Android's own handles move the
                          // start and end inside the words.
                          child: TextField(
                            controller: part,
                            readOnly: true,
                            autofocus: true,
                            showCursor: false,
                            maxLines: null,
                            enableInteractiveSelection: true,
                            style: t.body.copyWith(fontWeight: FontWeight.w600),
                            decoration: const InputDecoration.collapsed(
                              hintText: '',
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'One word fewer',
                        onPressed: last > first
                            ? () => words2(() => last--)
                            : null,
                        icon: const Icon(Symbols.remove),
                      ),
                      IconButton(
                        tooltip: 'One word more',
                        onPressed: last < words.length - 1
                            ? () => words2(() => last++)
                            : null,
                        icon: const Icon(Symbols.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Drag the handles to mark part of it',
                    style: t.meta.copyWith(color: c.text3),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final field in MarkField.values)
                        if (field !=
                            (state.isMandate
                                ? MarkField.date
                                : MarkField.dueDate))
                          ActionChip(
                            label: Text(_fieldName(field)),
                            onPressed: () {
                              final sel = part.selection;
                              final whole = part.text.length;
                              // A dragged, non-empty part is kept as chosen.
                              final dragged =
                                  sel.isValid &&
                                  !sel.isCollapsed &&
                                  (sel.start > 0 || sel.end < whole);
                              final base = words[first].start;
                              Navigator.pop(
                                context,
                                dragged
                                    ? (
                                        field,
                                        base + sel.start,
                                        base + sel.end,
                                        true,
                                      )
                                    : (field, base, words[last].end, false),
                              );
                            },
                          ),
                    ],
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, 'clear'),
                      icon: const Icon(Symbols.close),
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
    // After the sheet has animated out (disposing earlier crashes).
    Future<void>.delayed(const Duration(milliseconds: 500), part.dispose);
    if (picked == 'clear' && existing != null) {
      cubit.unmark(existing);
    } else if (picked case (
      final MarkField field,
      final int s,
      final int e,
      final bool exact,
    )) {
      if (!cubit.mark(field, s, e, exact: exact) && context.mounted) {
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
    MarkField.card => 'Card no.',
    MarkField.direction => 'Debit/credit word',
    MarkField.amount => 'Amount',
    MarkField.payee => 'Payee',
    MarkField.ref => 'Reference',
    MarkField.date => 'Date',
    MarkField.balance => 'Balance',
    MarkField.dueDate => 'Due date',
  };

  String _fieldArticle(MarkField f) => switch (f) {
    MarkField.account => 'an account number (4 digits)',
    MarkField.card => 'a card number (4 digits)',
    MarkField.amount => 'an amount',
    MarkField.balance => 'a balance',
    MarkField.ref => 'a reference',
    MarkField.date || MarkField.dueDate => 'a date',
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

  Future<void> _pickDueDate(BuildContext context, DateTime? current) async {
    final cubit = context.read<ReviewEditorCubit>();
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (day != null) cubit.setDueDate(day);
  }

  /// "Not a transaction" sheet (design 03j), then Undo (03k).
  Future<void> _notATransaction(BuildContext context) async {
    final cubit = context.read<ReviewEditorCubit>();
    final bank = cubit.bankShort();
    final skip = await showKSheet<bool>(
      context: context,
      builder: (context) => _NotATransactionSheet(bank: bank),
    );
    if (skip == null || !context.mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final undo = await cubit.notATransaction(skipSimilar: skip);
    if (undo == null) return;
    final more = undo.rawIds.length - 1;
    _offerUndo(
      messenger,
      more > 0
          ? 'Marked not a transaction, and $more more like it'
          : 'Marked not a transaction',
      undo,
    );
    if (cubit.state.item == null && nav.canPop()) nav.pop();
  }

  Future<void> _notABank(BuildContext context) async {
    final cubit = context.read<ReviewEditorCubit>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final undo = await cubit.notABank();
    if (undo == null) return;
    _offerUndo(messenger, '${item.raw.sender} is not a bank', undo);
    if (cubit.state.item == null && nav.canPop()) nav.pop();
  }

  static void _offerUndo(
    ScaffoldMessengerState messenger,
    String text,
    ReviewUndo undo,
  ) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          // Snackbars with an action stay until tapped by default; Undo is
          // a convenience, so let it time out.
          persist: false,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => getIt<ReviewService>().undo(undo),
          ),
        ),
      );
  }

  /// Which bank sent this (design 03g); "A bank not in k" → 03h.
  Future<void> _pickBank(BuildContext context) async {
    final cubit = context.read<ReviewEditorCubit>();
    final picked = await showBankPicker(
      context,
      banks: state.banks,
      title: 'Which bank sent this?',
      subtitle: 'k will read ${item.raw.sender} as that bank.',
      selectedId: state.bank?.id,
    );
    if (!context.mounted || picked == null) return;
    if (picked == newBankPick) {
      final choice = await showKSheet<BankChoice>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _NewBankSheet(
          sender: item.raw.sender,
          initial: state.bank?.newName ?? _guessBankName(item.raw.sender),
        ),
      );
      if (choice != null) cubit.setBank(choice);
    } else {
      cubit.setBank(BankChoice.existing(picked));
    }
  }

  /// "JD-HDFCBK-S" → "HDFC Bank": drop the operator prefix/suffix and a
  /// trailing BK/BNK. Only a starting point for the name field.
  static String _guessBankName(String sender) {
    final parts = sender.toUpperCase().split('-');
    var core = parts.length > 1 && parts.first.length == 2
        ? parts[1]
        : parts.first;
    core = core.replaceFirst(RegExp(r'(BNK|BK|BANK)$'), '');
    return core.isEmpty ? '' : '$core Bank';
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
    final picked = await showKSheet<(String?,)>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Symbols.short_text),
              title: const Text('From the message'),
              subtitle: const Text('Use the account number marked above'),
              onTap: () => Navigator.pop(context, (null,)),
            ),
            for (final a in accounts)
              ListTile(
                title: Text(a.long),
                trailing: a.id == state.accountId
                    ? const Icon(Symbols.check)
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
    final picked = await showKSheet<String>(
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
                      ? const Icon(Symbols.check)
                      : null,
                  onTap: () => Navigator.pop(context, cat.id),
                ),
              newCategoryTile(context, (c) => c.id),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    if (!state.categories.any((c) => c.id == picked)) {
      await cubit.reloadCategories();
    }
    cubit.setCategory(picked);
  }
}

/// Design 03j: confirm, optionally skipping messages shaped like this.
/// Pops true/false (skip similar), null on cancel.
class _NotATransactionSheet extends StatefulWidget {
  const _NotATransactionSheet({required this.bank});

  final String bank;

  @override
  State<_NotATransactionSheet> createState() => _NotATransactionSheetState();
}

class _NotATransactionSheetState extends State<_NotATransactionSheet> {
  var _skip = false;

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not a transaction', style: t.title),
            const SizedBox(height: 4),
            Text("k keeps the message but won't log a payment.", style: t.meta),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Skip messages like this',
                        style: t.body.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Similar ${widget.bank} messages skip Review. '
                        'Undo in Settings → Message formats.',
                        style: t.meta.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Switch(
                  value: _skip,
                  onChanged: (v) => setState(() => _skip = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _skip),
                  child: const Text('Not a transaction'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Design 03h: name a bank k doesn't have, plus its alert mail sender.
class _NewBankSheet extends StatefulWidget {
  const _NewBankSheet({required this.sender, required this.initial});

  final String sender;
  final String initial;

  @override
  State<_NewBankSheet> createState() => _NewBankSheetState();
}

class _NewBankSheetState extends State<_NewBankSheet> {
  late final _name = TextEditingController(text: widget.initial);
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.kt;
    final c = context.k;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A bank not in k', style: t.title),
            const SizedBox(height: 4),
            Text(
              'k reads ${widget.sender} as this bank from now on.',
              style: t.meta,
            ),
            const SizedBox(height: 16),
            TextField(
              style: context.kt.input,
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Bank name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Alert email from (optional)',
                hintText: 'e.g. hdfcbank.net',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add its address or domain to read its emails too.',
              style: t.meta.copyWith(color: c.text2),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          BankChoice.create(
                            _name.text.trim(),
                            emailSender: _email.text.trim(),
                          ),
                        ),
                  child: const Text('Add bank'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
