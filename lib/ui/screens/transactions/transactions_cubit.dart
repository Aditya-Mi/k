import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:txn_parser/txn_parser.dart';

import '../../../data/db/app_database.dart' hide ParserTemplate, SenderRule;
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../theme/bands.dart';
import '../../widgets/month_note_panel.dart';

class TransactionsState extends Equatable {
  const TransactionsState({
    required this.filter,
    required this.summary,
    this.txns = const [],
    this.upcoming = const [],
    this.accounts = const [],
    this.categories = const [],
    this.reviewCount = 0,
    this.lastSync,
    this.loaded = false,
  });

  final TxnFilter filter;
  final MonthSummary summary;
  final List<TxnView> txns;
  final List<UpcomingView> upcoming;
  final List<AccountView> accounts;
  final List<Category> categories;
  final int reviewCount;
  final DateTime? lastSync;
  final bool loaded;

  DateTime get month => filter.from;

  bool get isCurrentMonth {
    final now = DateTime.now();
    return month.year == now.year && month.month == now.month;
  }

  bool get narrowed =>
      filter.accountIds.isNotEmpty ||
      filter.categoryIds.isNotEmpty ||
      filter.direction != null ||
      filter.query.isNotEmpty;

  TransactionsState copyWith({
    TxnFilter? filter,
    MonthSummary? summary,
    List<TxnView>? txns,
    List<UpcomingView>? upcoming,
    List<AccountView>? accounts,
    List<Category>? categories,
    int? reviewCount,
    DateTime? lastSync,
    bool? loaded,
  }) => TransactionsState(
    filter: filter ?? this.filter,
    summary: summary ?? this.summary,
    txns: txns ?? this.txns,
    upcoming: upcoming ?? this.upcoming,
    accounts: accounts ?? this.accounts,
    categories: categories ?? this.categories,
    reviewCount: reviewCount ?? this.reviewCount,
    lastSync: lastSync ?? this.lastSync,
    loaded: loaded ?? this.loaded,
  );

  @override
  List<Object?> get props => [
    filter, summary.spentMinor, summary.inMinor, summary.spends, txns, //
    upcoming, accounts, categories, reviewCount, lastSync, loaded,
  ];
}

MonthSummary summarize(DateTime month, List<TxnView> txns) {
  var spent = 0;
  var came = 0;
  var spends = 0;
  final bands = List.filled(Bands.count, 0);
  for (final t in txns) {
    // Own-account moves and cash payments (counted at the ATM) are out.
    if (!t.countsInTotals) continue;
    if (t.isDebit) {
      spent += t.amountMinor;
      spends++;
      bands[Bands.of(t.amountMinor)] += t.amountMinor;
    } else {
      came += t.amountMinor;
    }
  }
  return MonthSummary(
    month: month,
    spentMinor: spent,
    inMinor: came,
    spends: spends,
    bandTotals: bands,
  );
}

class TransactionsCubit extends Cubit<TransactionsState> {
  TransactionsCubit(this._ledger, this._settings, {DateTime? now})
    : super(_initial(now ?? DateTime.now())) {
    final today = now ?? DateTime.now();
    _subs.addAll([
      _ledger.watchUpcoming(today).listen((u) => _emit(upcoming: u)),
      _ledger.watchReviewCount().listen((n) => _emit(reviewCount: n)),
      _ledger.watchAccounts().listen((a) => _emit(accounts: a)),
      _ledger.watchCategories().listen((c) => _emit(categories: c)),
      _settings
          .watchDate(SettingsRepository.smsLastSyncAt)
          .listen((d) => _emit(lastSync: d)),
    ]);
    _watchList();
    _watchPeriod();
  }

  static TransactionsState _initial(DateTime now) {
    final f = TxnFilter.month(now);
    return TransactionsState(filter: f, summary: MonthSummary.empty(f.from));
  }

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<List<TxnView>>? _list;
  StreamSubscription<List<TxnView>>? _period;

  void _emit({
    List<UpcomingView>? upcoming,
    int? reviewCount,
    List<AccountView>? accounts,
    List<Category>? categories,
    DateTime? lastSync,
  }) {
    if (isClosed) return;
    emit(
      state.copyWith(
        upcoming: upcoming,
        reviewCount: reviewCount,
        accounts: accounts,
        categories: categories,
        lastSync: lastSync,
      ),
    );
  }

  void _watchList() {
    _list?.cancel();
    _list = _ledger.watchTransactions(state.filter).listen((txns) {
      if (!isClosed) emit(state.copyWith(txns: txns, loaded: true));
    });
  }

  void _watchPeriod() {
    _period?.cancel();
    final f = state.filter;
    _period = _ledger.watchTransactions(f.periodOnly).listen((txns) {
      if (!isClosed) emit(state.copyWith(summary: summarize(f.from, txns)));
    });
  }

  void _setFilter(TxnFilter f) {
    final periodChanged =
        f.from != state.filter.from || f.to != state.filter.to;
    emit(state.copyWith(filter: f));
    _watchList();
    if (periodChanged) _watchPeriod();
  }

  void setMonth(DateTime month) {
    final m = TxnFilter.month(month);
    _setFilter(state.filter.copyWith(from: m.from, to: m.to));
  }

  void setAccounts(Set<String> ids) =>
      _setFilter(state.filter.copyWith(accountIds: ids));

  void setCategories(Set<String> ids) =>
      _setFilter(state.filter.copyWith(categoryIds: ids));

  void setDirection(Direction? d) =>
      _setFilter(state.filter.copyWith(direction: () => d));

  void setQuery(String q) {
    if (q == state.filter.query) return;
    _setFilter(state.filter.copyWith(query: q));
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _list?.cancel();
    await _period?.cancel();
    return super.close();
  }
}
