import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/sms_controller.dart';
import '../../app/updates.dart';
import '../../data/emis/emi_service.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../di.dart';
import '../motion.dart';
import '../theme/k_theme.dart';
import '../widgets/k_icons.dart';
import 'accounts/accounts_screen.dart';
import 'review/review_queue_screen.dart';
import 'subscriptions/subscriptions_screen.dart';
import 'summary/summary_screen.dart';
import 'transactions/add_payment_screen.dart';
import 'transactions/transactions_cubit.dart';
import 'transactions/transactions_screen.dart';

/// Bottom navigation: Transactions, Review, Recurring, Accounts, Summary.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.sms});

  final SmsController sms;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // The dialog sits under the lock overlay until k is unlocked.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => checkForUpdateOnLaunch(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TransactionsCubit(
        getIt<LedgerRepository>(),
        getIt<SettingsRepository>(),
        instalments: (month) => getIt<EmiService>().virtualInstalments([month]),
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: FadeThroughStack(
            index: _tab,
            children: [
              TransactionsScreen(
                smsGranted: widget.sms.smsGranted,
                onOpenReview: () => setState(() => _tab = 1),
              ),
              const ReviewQueueScreen(),
              const SubscriptionsScreen(),
              const AccountsScreen(asTab: true),
              const SummaryScreen(),
            ],
          ),
        ),
        // Add payment in thumb reach, Transactions only (DESIGN.md FAB).
        floatingActionButton: _tab == 0 ? const _AddFab() : null,
        bottomNavigationBar:
            BlocSelector<TransactionsCubit, TransactionsState, int>(
              selector: (s) => s.reviewCount,
              builder: (context, reviewCount) => NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  const NavigationDestination(
                    icon: KIcon(KIcons.transactions),
                    label: 'Transactions',
                  ),
                  NavigationDestination(
                    icon: _ReviewBadge(
                      count: reviewCount,
                      child: const KIcon(KIcons.review),
                    ),
                    label: 'Review',
                  ),
                  const NavigationDestination(
                    icon: KIcon(KIcons.recurring),
                    label: 'Recurring',
                  ),
                  const NavigationDestination(
                    icon: KIcon(KIcons.accounts),
                    label: 'Accounts',
                  ),
                  const NavigationDestination(
                    icon: KIcon(KIcons.summary),
                    label: 'Summary',
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab();

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return FloatingActionButton.extended(
      tooltip: 'Add payment',
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      backgroundColor: c.text,
      foregroundColor: c.onInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Symbols.add),
      label: Text('Add', style: context.kt.title.copyWith(color: c.onInk)),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const AddPaymentScreen(),
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
