import 'package:flutter/material.dart';

import '../../../app/updates.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../../data/ingest/sms_sync.dart';
import '../../../data/repositories/ledger_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/review/learned_formats.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/date_pick.dart';
import '../../../data/db/app_database.dart' show Category;
import '../categories/categories_screen.dart';
import '../review/learned_formats_screen.dart';
import 'appearance_settings.dart';
import 'backup_settings.dart';
import 'bank_settings.dart';
import 'email_settings.dart';
import 'notification_settings.dart';
import 'privacy_settings.dart';
import 'settings_parts.dart';

/// Settings (design 06l): a short list grouped as Reading, Your data and
/// This phone; detail lives on sub-pages.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    void open(String title, List<Widget> children) => Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => _SubPage(title: title, children: children),
          ),
        );
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
          const SettingsHead('Reading'),
          SettingsItem(
            icon: Icons.sms_outlined,
            title: 'Messages and email',
            subtitle: 'Banks k reads and your email inboxes',
            onTap: () => open('Messages and email', const [
              BankSettings(),
              EmailSettings(),
            ]),
            trailing: const SettingsChevron(),
          ),
          SettingsItem(
            icon: Icons.sync_rounded,
            title: 'Sync',
            subtitle: 'SMS access, checks, and merging SMS with email',
            onTap: () => open('Sync', const [_SyncSection()]),
            trailing: const SettingsChevron(),
          ),
          const SettingsHead('Your data'),
          StreamBuilder<List<Category>>(
            stream: getIt<LedgerRepository>().watchCategories(),
            builder: (context, snap) {
              final mine = (snap.data ?? const <Category>[])
                  .where((c) => !c.isSystem)
                  .length;
              return SettingsItem(
                icon: Icons.category_outlined,
                title: 'Categories',
                subtitle: mine == 0
                    ? 'Add your own, rename or hide built-in ones'
                    : '$mine of your own · add, rename or hide',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const CategoriesScreen(),
                  ),
                ),
                trailing: const SettingsChevron(),
              );
            },
          ),
          StreamBuilder<List<LearnedFormat>>(
            stream: getIt<LearnedFormats>().watch(),
            builder: (context, snap) {
              final n = snap.data?.length;
              return SettingsItem(
                icon: Icons.school_outlined,
                title: 'Message formats',
                subtitle: n == null
                    ? '…'
                    : n == 0
                    ? 'None yet. Fixing a message in Review teaches k its format.'
                    : '$n learned from your corrections',
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
          SettingsItem(
            icon: Icons.cloud_upload_outlined,
            title: 'Backup and export',
            subtitle: 'Encrypted Drive backup, backup files, CSV',
            onTap: () => open('Backup and export', const [BackupSettings()]),
            trailing: const SettingsChevron(),
          ),
          const SettingsHead('This phone'),
          SettingsItem(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Payments, review, reminders',
            onTap: () => open('Notifications', const [NotificationSettings()]),
            trailing: const SettingsChevron(),
          ),
          const PrivacySettings(showHead: false),
          const AppearanceSettings(showHead: false),
          const AboutSettings(),
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

/// A settings sub-page holding existing sections.
class _SubPage extends StatelessWidget {
  const _SubPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(title),
    ),
    body: ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    ),
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
