import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/sms_controller.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../di.dart';
import '../theme/k_theme.dart';
import '../widgets/common.dart';
import 'review/review_queue_screen.dart';
import 'subscriptions/subscriptions_screen.dart';
import 'transactions/transactions_cubit.dart';
import 'transactions/transactions_screen.dart';

/// Bottom navigation: Transactions, Review, Subscriptions, Summary.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.sms});

  final SmsController sms;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TransactionsCubit(
        getIt<LedgerRepository>(),
        getIt<SettingsRepository>(),
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab,
            children: [
              TransactionsScreen(
                smsGranted: widget.sms.smsGranted,
                onOpenReview: () => setState(() => _tab = 1),
              ),
              const ReviewQueueScreen(),
              const SubscriptionsScreen(),
              const _Later(
                title: 'Summary',
                body: 'Where the month went, by category.',
              ),
            ],
          ),
        ),
        bottomNavigationBar:
            BlocSelector<TransactionsCubit, TransactionsState, int>(
              selector: (s) => s.reviewCount,
              builder: (context, reviewCount) => NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long_rounded),
                    label: 'Transactions',
                  ),
                  NavigationDestination(
                    icon: _ReviewBadge(
                      count: reviewCount,
                      child: const Icon(Icons.rule_rounded),
                    ),
                    label: 'Review',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.autorenew_rounded),
                    label: 'Subscriptions',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.donut_large_rounded),
                    label: 'Summary',
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

/// Neutral badge: text-coloured disc, bg-coloured count (The Calm Count Rule).
class _ReviewBadge extends StatelessWidget {
  const _ReviewBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    backgroundColor: context.k.text,
    textColor: context.k.onInk,
    label: Text(count > 99 ? '99+' : '$count'),
    child: child,
  );
}

class _Later extends StatelessWidget {
  const _Later({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(title, style: context.kt.headline),
      ),
      Expanded(
        child: Center(
          child: EmptyState(title: 'Not built yet', body: body),
        ),
      ),
    ],
  );
}
