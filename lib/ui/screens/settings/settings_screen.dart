import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/ingest/sms_sync.dart';
import '../../../data/repositories/ledger_models.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/review/learned_formats.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/date_pick.dart';
import '../accounts/accounts_screen.dart';
import '../review/learned_formats_screen.dart';
import 'appearance_settings.dart';
import 'backup_settings.dart';
import 'bank_settings.dart';
import 'email_settings.dart';
import 'notification_settings.dart';
import 'privacy_settings.dart';
import 'settings_parts.dart';

/// Settings (design 06): accounts, banks, email, sync, notifications,
/// backup, appearance, privacy, message formats.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _AccountsSection(),
          const BankSettings(),
          const EmailSettings(),
          const _SyncSection(),
          const NotificationSettings(),
          const BackupSettings(),
          const AppearanceSettings(),
          const PrivacySettings(),
          const SettingsHead('Message formats'),
          StreamBuilder<List<LearnedFormat>>(
            stream: getIt<LearnedFormats>().watch(),
            builder: (context, snap) {
              final n = snap.data?.length;
              return SettingsItem(
                icon: Icons.school_outlined,
                title: 'Learned in Review',
                subtitle: n == null
                    ? '…'
                    : n == 0
                    ? 'None yet. Fixing a message in Review teaches k its format.'
                    : '$n ${n == 1 ? 'format' : 'formats'} k reads now',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const LearnedFormatsScreen(),
                  ),
                ),
                trailing: const SettingsChevron(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: c.text3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Messages are read and stored on this phone only, in an '
                    'encrypted database. Backups are encrypted here before '
                    'they reach your own Google Drive.',
                    style: t.meta.copyWith(color: c.text3, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Accounts k has seen in messages; rename or merge on the Accounts screen.
class _AccountsSection extends StatelessWidget {
  const _AccountsSection();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AccountView>>(
    stream: getIt<LedgerRepository>().watchAccounts(),
    builder: (context, snap) {
      final accounts = snap.data ?? const <AccountView>[];
      void open() => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AccountsScreen()));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsHead('Accounts', note: 'Added from messages'),
          if (accounts.isEmpty)
            const SettingsItem(
              icon: Icons.account_balance_wallet_outlined,
              title: 'None yet',
              subtitle: 'Accounts appear as bank messages name them',
            )
          else
            for (final a in accounts)
              SettingsItem(
                icon: a.isCard
                    ? Icons.credit_card_outlined
                    : Icons.account_balance_wallet_outlined,
                title: a.nickname ?? a.long,
                subtitle: [
                  if (a.nickname != null) a.long,
                  if (a.includes.isNotEmpty)
                    'includes ${a.includes.join(', ')}',
                  'tap to rename or merge',
                ].join(' · '),
                onTap: open,
                trailing: const SettingsChevron(),
              ),
        ],
      );
    },
  );
}

/// SMS capture health, catch-up and the SMS/email merge window.
class _SyncSection extends StatefulWidget {
  const _SyncSection();

  @override
  State<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<_SyncSection> {
  final _settings = getIt<SettingsRepository>();
  PermissionStatus? _sms;
  PermissionStatus? _battery;
  bool _checking = false;
  late final AppLifecycleListener _lifecycle;

  static const _dedupKey = 'dedup.windowMinutes';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final sms = await Permission.sms.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    if (!mounted) return;
    setState(() {
      _sms = sms;
      _battery = battery;
    });
  }

  Future<void> _fixSms() async {
    final status = await Permission.sms.request();
    if (!status.isGranted) await openAppSettings();
    await _refresh();
  }

  Future<void> _run(Future<int> Function() job) async {
    setState(() => _checking = true);
    var logged = 0;
    try {
      logged = await job();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          logged == 0
              ? 'Up to date'
              : '$logged new ${logged == 1 ? 'payment' : 'payments'} logged',
        ),
      ),
    );
  }

  Future<void> _importOlder() async {
    final day = await pickImportStart(context);
    if (day == null || !mounted) return;
    await _run(() => getIt<SmsSync>().importHistory(day));
  }

  Future<void> _pickWindow(int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Treat SMS and email as one payment within',
                  style: context.kt.title,
                ),
              ),
            ),
            for (final m in const [5, 10, 30, 60])
              ListTile(
                title: Text(_minutes(m)),
                trailing: m == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _settings.set(_dedupKey, '$picked');
  }

  static String _minutes(int m) => m == 60 ? '1 hour' : '$m minutes';

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final smsOk = _sms?.isGranted ?? false;
    final batteryOk = _battery?.isGranted ?? false;
    final sync = getIt<SmsSync>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsHead('Sync'),
        SettingsItem(
          icon: smsOk ? Icons.sms_outlined : Icons.sms_failed_outlined,
          iconColor: _sms == null || smsOk ? null : c.alert,
          title: _sms == null ? 'SMS' : (smsOk ? 'SMS allowed' : 'SMS off'),
          subtitle: smsOk
              ? 'k reads bank SMS as they arrive'
              : (_sms?.isPermanentlyDenied ?? false)
              ? 'If Android shows no prompt: App info → ⋮ → Allow restricted '
                    'settings, then Permissions → SMS → Allow.'
              : 'Tap to allow. Payments by SMS stop until you do.',
          subtitleColor: _sms == null || smsOk ? null : c.alert,
          onTap: smsOk ? openAppSettings : _fixSms,
          trailing: const SettingsChevron(),
        ),
        SettingsItem(
          icon: Icons.battery_full_rounded,
          title: batteryOk ? 'Battery: unrestricted' : 'Battery: limited',
          subtitle: batteryOk
              ? 'k can read messages while closed'
              : 'Tap to allow, or some payments log only when you open k',
          onTap: batteryOk
              ? null
              : () async {
                  await Permission.ignoreBatteryOptimizations.request();
                  await _refresh();
                },
          trailing: batteryOk ? null : const SettingsChevron(),
        ),
        StreamBuilder<DateTime?>(
          stream: _settings.watchDate(SettingsRepository.smsLastSyncAt),
          builder: (context, snap) => SettingsItem(
            icon: Icons.refresh_rounded,
            title: 'Check SMS now',
            subtitle: snap.data == null
                ? 'Never checked'
                : 'Last checked ${dayMonth(snap.data!)}, ${hhmm(snap.data!)}',
            onTap: _checking || !smsOk
                ? null
                : () => _run(
                    () async =>
                        await sync.drainPending() + await sync.catchUp(),
                  ),
            trailing: _checking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ),
        SettingsItem(
          icon: Icons.history_rounded,
          title: 'Read past SMS',
          subtitle: 'From a date you pick. Already logged ones are skipped.',
          onTap: _checking || !smsOk ? null : _importOlder,
          trailing: const SettingsChevron(),
        ),
        const SettingsItem(
          icon: Icons.schedule_rounded,
          title: 'Check email',
          subtitle: 'Every hour, and when you open k',
        ),
        StreamBuilder<String?>(
          stream: _settings.watch(_dedupKey),
          builder: (context, snap) {
            final m = int.tryParse(snap.data ?? '') ?? 10;
            return SettingsItem(
              icon: Icons.merge_rounded,
              title: 'Treat as the same payment',
              subtitle:
                  'Same amount and account within ${_minutes(m)}, by SMS and email',
              onTap: () => _pickWindow(m),
              trailing: const SettingsChevron(),
            );
          },
        ),
      ],
    );
  }
}
