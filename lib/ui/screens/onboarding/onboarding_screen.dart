import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/ingest/sms_sync.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/date_pick.dart';
import 'onboarding_cubit.dart';

/// First run: SMS access (incl. the sideload "restricted settings" unlock),
/// background running, and how much inbox history to import.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        OnboardingCubit(getIt<SmsSync>(), getIt<SettingsRepository>())
          ..refresh(),
    child: _OnboardingView(onDone: onDone),
  );
}

class _OnboardingView extends StatefulWidget {
  const _OnboardingView({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<_OnboardingView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from App info / battery settings → re-read permission state.
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<OnboardingCubit>().refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return BlocConsumer<OnboardingCubit, OnboardingState>(
      listenWhen: (a, b) => !a.done && b.done,
      listener: (_, _) => widget.onDone(),
      builder: (context, s) {
        final cubit = context.read<OnboardingCubit>();
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    children: [
                      Text('k', style: t.wordmark),
                      const SizedBox(height: 24),
                      Text('Log payments from bank SMS', style: t.headline),
                      const SizedBox(height: 8),
                      Text(
                        'Messages are read and stored encrypted on this phone. '
                        'They never leave it.',
                        style: t.body.copyWith(color: c.text2),
                      ),
                      const SizedBox(height: 24),
                      _Step(
                        number: 1,
                        title: 'SMS access',
                        done: s.smsGranted,
                        body: s.smsBlocked
                            ? 'Android blocks this. Open App info, tap ⋮ → '
                                  'Allow restricted settings, then tap Allow.'
                            : 'Logs new payments and reads past bank alerts.',
                        action: s.smsGranted
                            ? null
                            : Wrap(
                                spacing: 8,
                                children: [
                                  if (s.smsBlocked)
                                    OutlinedButton(
                                      onPressed: cubit.openAppInfo,
                                      child: const Text('Open App info'),
                                    ),
                                  OutlinedButton(
                                    onPressed: cubit.requestSms,
                                    child: const Text('Allow'),
                                  ),
                                ],
                              ),
                      ),
                      _Step(
                        number: 2,
                        title: 'Log while k is closed',
                        done: s.battery?.isGranted ?? false,
                        body:
                            'Remove battery limits so payments log when k is '
                            'closed. Also set App info → Battery → Unrestricted.',
                        action: (s.battery?.isGranted ?? false)
                            ? null
                            : Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: cubit.requestBattery,
                                    child: const Text('Allow'),
                                  ),
                                  OutlinedButton(
                                    onPressed: cubit.openAppInfo,
                                    child: const Text('App info'),
                                  ),
                                ],
                              ),
                      ),
                      _Step(
                        number: 3,
                        title: 'Past messages',
                        body: 'Read bank alerts already in your inbox.',
                        action: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final h in HistoryRange.values)
                                  ChoiceChip(
                                    label: Text(h.label),
                                    selected: s.history == h,
                                    showCheckmark: false,
                                    onSelected: s.importing
                                        ? null
                                        : (_) => h == HistoryRange.custom
                                              ? _pickDate(context, s)
                                              : cubit.chooseHistory(h),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(switch (s.sinceAt(DateTime.now())) {
                              null => 'Only new messages from now on',
                              final d => 'From ${fullDay(d)}',
                            }, style: t.meta),
                          ],
                        ),
                      ),
                      if (s.error != null) ...[
                        const SizedBox(height: 8),
                        Text(s.error!, style: t.body.copyWith(color: c.alert)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: s.importing
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              'Reading messages… ${s.logged} payments logged',
                              style: t.meta,
                            ),
                          ],
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: s.smsGranted ? cubit.finish : null,
                            child: const Text('Start logging'),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _pickDate(BuildContext context, OnboardingState s) async {
  final cubit = context.read<OnboardingCubit>();
  final day = await pickImportStart(context, initial: s.customSince);
  if (day != null) cubit.chooseSince(day);
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    this.action,
    this.done = false,
  });

  final int number;
  final String title;
  final String body;
  final Widget? action;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: c.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: done
                ? Icon(Icons.check_circle_rounded, size: 20, color: c.text)
                : Text('$number', style: t.title.copyWith(color: c.text2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.title),
                const SizedBox(height: 4),
                Text(body, style: t.body.copyWith(color: c.text2)),
                if (action != null) ...[const SizedBox(height: 12), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
