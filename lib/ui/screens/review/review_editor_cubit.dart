import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../../data/db/app_database.dart' hide ParserTemplate, SenderRule;
import '../../../data/db/enums.dart';
import '../../../data/repositories/bank_repository.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../data/review/field_marks.dart';
import '../../../data/review/review_service.dart';

class ReviewEditorState {
  const ReviewEditorState({
    this.queue = const [],
    this.index = 0,
    this.marks = const [],
    this.direction = Direction.debit,
    this.kind = TemplateKind.transaction,
    this.bank,
    this.dueDate,
    this.banks = const [],
    this.amountMinor,
    this.payee,
    this.ref,
    this.occurredAt,
    this.accountId,
    this.categoryId,
    this.learn = true,
    this.saving = false,
    this.accounts = const [],
    this.categories = const [],
    this.loaded = false,
    this.lastResult,
    this.bankNames = const {},
  });

  final List<ReviewItem> queue;
  final int index;
  final List<FieldMark> marks;
  final Direction direction;
  final TemplateKind kind;

  /// Unknown sender only: which bank the owner said it is.
  final BankChoice? bank;
  final DateTime? dueDate;
  final List<BankView> banks;

  /// Typed overrides (null → from marks).
  final int? amountMinor;
  final String? payee;
  final String? ref;
  final DateTime? occurredAt;
  final String? accountId;
  final String? categoryId;
  final bool learn;
  final bool saving;
  final List<AccountView> accounts;
  final List<Category> categories;
  final bool loaded;
  final Map<String, String> bankNames;

  /// Set right after a save, for the learned overlay / snackbar.
  final ({SaveResult result, ParsedFields fields, String bank})? lastResult;

  ReviewItem? get item => index < queue.length ? queue[index] : null;

  bool get isMandate => kind == TemplateKind.mandate;

  ReviewDraft get draft => ReviewDraft(
    marks: marks,
    direction: direction,
    kind: kind,
    bank: bank,
    dueDate: dueDate,
    amountMinor: amountMinor,
    accountId: accountId,
    payee: payee,
    ref: ref,
    occurredAt: occurredAt,
    categoryId: categoryId,
    learn: learn,
  );

  ReviewEditorState copyWith({
    List<ReviewItem>? queue,
    int? index,
    List<FieldMark>? marks,
    Direction? direction,
    TemplateKind? kind,
    BankChoice? Function()? bank,
    DateTime? Function()? dueDate,
    List<BankView>? banks,
    int? Function()? amountMinor,
    String? Function()? payee,
    String? Function()? ref,
    DateTime? Function()? occurredAt,
    String? Function()? accountId,
    String? Function()? categoryId,
    bool? learn,
    bool? saving,
    List<AccountView>? accounts,
    List<Category>? categories,
    bool? loaded,
    Map<String, String>? bankNames,
    ({SaveResult result, ParsedFields fields, String bank})? Function()?
    lastResult,
  }) => ReviewEditorState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    marks: marks ?? this.marks,
    direction: direction ?? this.direction,
    kind: kind ?? this.kind,
    bank: bank != null ? bank() : this.bank,
    dueDate: dueDate != null ? dueDate() : this.dueDate,
    banks: banks ?? this.banks,
    amountMinor: amountMinor != null ? amountMinor() : this.amountMinor,
    payee: payee != null ? payee() : this.payee,
    ref: ref != null ? ref() : this.ref,
    occurredAt: occurredAt != null ? occurredAt() : this.occurredAt,
    accountId: accountId != null ? accountId() : this.accountId,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    learn: learn ?? this.learn,
    saving: saving ?? this.saving,
    accounts: accounts ?? this.accounts,
    categories: categories ?? this.categories,
    loaded: loaded ?? this.loaded,
    bankNames: bankNames ?? this.bankNames,
    lastResult: lastResult != null ? lastResult() : this.lastResult,
  );
}

class ReviewEditorCubit extends Cubit<ReviewEditorState> {
  ReviewEditorCubit(
    this._review,
    this._ledger,
    this._banks, {
    required String startRawId,
  }) : super(const ReviewEditorState()) {
    _load(startRawId);
  }

  final ReviewService _review;
  final LedgerRepository _ledger;
  final BankRepository _banks;

  Future<void> _load(String? rawId) async {
    final queue = await _review.watchQueue().first;
    final accounts = await _ledger.watchAccounts().first;
    final categories = await _ledger.watchCategories().first;
    final banks = await _ledger.bankNames();
    final bankViews = await _banks.watchBanks().first;
    if (isClosed) return;
    var index = queue.indexWhere((i) => i.raw.id == rawId);
    if (index < 0) {
      index = state.index.clamp(0, queue.isEmpty ? 0 : queue.length - 1);
    }
    emit(
      _fresh(queue, index).copyWith(
        accounts: accounts,
        categories: categories,
        bankNames: banks,
        banks: bankViews,
        loaded: true,
        lastResult: () => state.lastResult,
      ),
    );
  }

  /// Draft reset to the parser's guesses for queue[index].
  ReviewEditorState _fresh(List<ReviewItem> queue, int index) {
    if (queue.isEmpty) {
      return ReviewEditorState(
        accounts: state.accounts,
        categories: state.categories,
        bankNames: state.bankNames,
        banks: state.banks,
      );
    }
    final item = queue[index];
    final mandate = item.guess.kind == TemplateKind.mandate;
    var marks = prefillMarks(item.text, item.guess.fields);
    if (mandate) marks = _swapDate(marks, toDue: true);
    return ReviewEditorState(
      queue: queue,
      index: index,
      marks: marks,
      direction: item.guess.fields.direction ?? Direction.debit,
      kind: mandate ? TemplateKind.mandate : TemplateKind.transaction,
      accounts: state.accounts,
      categories: state.categories,
      bankNames: state.bankNames,
      banks: state.banks,
      learn: state.learn,
    );
  }

  ParsedFields fields() => _review.fieldsOf(state.item!, state.draft);

  /// "Axis Bank ··1234", "Axis Bank ··1234 · new", or the bank's only
  /// savings account when the message names none.
  String accountLabel() {
    final item = state.item!;
    final bankId = chosenBankId();
    if (state.accountId != null) {
      final a = state.accounts
          .where((a) => a.id == state.accountId)
          .firstOrNull;
      if (a != null) return a.long;
    }
    final bankAccounts = state.accounts.where(
      (a) => bankId != null && a.bankId == bankId,
    );
    final last4 = fields().last4;
    if (last4 != null) {
      final hit = bankAccounts.where((a) => a.last4 == last4).firstOrNull;
      if (hit != null) return hit.long;
      final hitFolded = bankAccounts
          .where((a) => a.includes.any((s) => s.endsWith(last4)))
          .firstOrNull;
      if (hitFolded != null) return hitFolded.long;
      return '${_bankName(item)} ··$last4 · new';
    }
    final savings = bankAccounts
        .where(
          (a) =>
              a.last4 != null &&
              (a.type == AccountType.savings || a.type == AccountType.current),
        )
        .toList();
    if (savings.length == 1) return savings.single.long;
    return '${_bankName(item)} · no account number';
  }

  List<AccountView> bankAccounts() {
    final bankId = chosenBankId();
    return state.accounts.where((a) => a.bankId == bankId).toList();
  }

  /// The message's bank, or the one the owner picked for an unknown sender
  /// (null while unpicked or when it is a new bank).
  String? chosenBankId() => state.item?.bankId ?? state.bank?.id;

  String _bankName(ReviewItem item) {
    final id = chosenBankId();
    if (id != null) return state.bankNames[id] ?? id;
    return state.bank?.newName ?? 'this bank';
  }

  /// "Axis", "Kotak", "BOB"; "HDFC" for a new "HDFC Bank".
  String bankShort() =>
      bankShortName(chosenBankId() ?? '', _bankName(state.item!));

  /// Full name of the picked bank, for the Bank row (null = not picked).
  String? bankLabel() {
    final b = state.bank;
    if (b == null) return null;
    return b.newName ?? state.bankNames[b.id] ?? b.id;
  }

  void setBank(BankChoice b) =>
      emit(state.copyWith(bank: () => b, accountId: () => null));

  /// Payment ↔ AutoPay alert. A DATE mark becomes DUE ON (and back).
  void setKind(TemplateKind kind) {
    if (kind == state.kind) return;
    emit(
      state.copyWith(
        kind: kind,
        marks: _swapDate(state.marks, toDue: kind == TemplateKind.mandate),
        dueDate: () => null,
      ),
    );
  }

  static List<FieldMark> _swapDate(
    List<FieldMark> marks, {
    required bool toDue,
  }) {
    final from = toDue ? MarkField.date : MarkField.dueDate;
    final to = toDue ? MarkField.dueDate : MarkField.date;
    return [
      for (final m in marks)
        m.field == from ? FieldMark(to, m.start, m.end) : m,
    ];
  }

  /// Marks [start, end) as [field] after trimming to what the field holds.
  /// Returns false when the selection can't be that field.
  bool mark(MarkField field, int start, int end) {
    final text = state.item!.text;
    final range = trimToField(text, field, start, end);
    if (range == null) return false;
    final (s, e) = range;
    final marks = [
      for (final m in state.marks)
        if (m.field != field && !m.overlaps(s, e)) m,
      FieldMark(field, s, e),
    ]..sort((a, b) => a.start.compareTo(b.start));
    emit(
      state.copyWith(
        marks: marks,
        // A fresh mark wins over a typed value for that field.
        amountMinor: field == MarkField.amount ? () => null : null,
        payee: field == MarkField.payee ? () => null : null,
        ref: field == MarkField.ref ? () => null : null,
        occurredAt: field == MarkField.date ? () => null : null,
        dueDate: field == MarkField.dueDate ? () => null : null,
        accountId: field == MarkField.account ? () => null : null,
      ),
    );
    return true;
  }

  void unmark(FieldMark m) =>
      emit(state.copyWith(marks: [...state.marks]..remove(m)));

  void setDirection(Direction d) => emit(state.copyWith(direction: d));
  void setAmount(int minor) => emit(state.copyWith(amountMinor: () => minor));
  void setPayee(String v) => emit(state.copyWith(payee: () => v));
  void setRef(String v) => emit(state.copyWith(ref: () => v));
  void setDate(DateTime d) => emit(state.copyWith(occurredAt: () => d));
  void setDueDate(DateTime d) => emit(state.copyWith(dueDate: () => d));
  void setAccount(String? id) => emit(state.copyWith(accountId: () => id));

  /// After "New category" in the picker.
  Future<void> reloadCategories() async {
    final categories = await _ledger.watchCategories().first;
    if (!isClosed) emit(state.copyWith(categories: categories));
  }

  void setCategory(String id) => emit(state.copyWith(categoryId: () => id));
  void setLearn(bool v) => emit(state.copyWith(learn: v));

  Future<void> save() async {
    final item = state.item;
    if (item == null || state.saving) return;
    emit(state.copyWith(saving: true));
    final parsed = fields();
    try {
      final result = await _review.save(item, state.draft);
      emit(
        state.copyWith(
          saving: false,
          lastResult: () => (result: result, fields: parsed, bank: bankShort()),
        ),
      );
      await _load(null);
    } catch (_) {
      emit(state.copyWith(saving: false));
      rethrow;
    }
  }

  Future<ReviewUndo?> notATransaction({bool skipSimilar = false}) async {
    final item = state.item;
    if (item == null) return null;
    final undo = await _review.notATransaction(item, skipSimilar: skipSimilar);
    await _load(null);
    return undo;
  }

  Future<ReviewUndo?> notABank() async {
    final item = state.item;
    if (item == null) return null;
    final undo = await _review.notABank(item);
    await _load(null);
    return undo;
  }

  void consumeResult() => emit(state.copyWith(lastResult: () => null));

  void skip() {
    if (state.queue.length < 2) return;
    final next = (state.index + 1) % state.queue.length;
    emit(_fresh(state.queue, next).copyWith(loaded: true));
  }
}
