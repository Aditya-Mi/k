import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:txn_parser/txn_parser.dart' show Channel;

import '../../widgets/k_sheet.dart';

import '../../../data/ingest/ingestion_service.dart';
import '../../../data/repositories/bank_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../../widgets/bank_picker.dart';
import '../../widgets/text_prompt.dart';
import 'banks_screen.dart';
import 'settings_parts.dart';

/// Settings → Banks (design 06): which SMS headers and email senders k reads
/// for each bank, and adding one when a bank starts using a new sender.
class BankSettings extends StatelessWidget {
  const BankSettings({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<BankView>>(
    stream: getIt<BankRepository>().watchBanks(),
    builder: (context, snap) {
      final banks = snap.data ?? const <BankView>[];
      // Only banks you use here; every bank k reads is one tap away (06k).
      final yours = banks.where((b) => b.inUse).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsHead('Banks'),
          for (final b in yours)
            SettingsItem(
              icon: bankIcon(b),
              title: b.name,
              subtitle: bankSenders(b),
              onTap: () => addBankSender(context, banks, bank: b),
              trailing: const SettingsChevron(),
            ),
          SettingsItem(
            icon: Symbols.format_list_bulleted,
            title: 'All banks k reads',
            subtitle: '${banks.length} banks',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BanksScreen()),
            ),
            trailing: const SettingsChevron(),
          ),
          SettingsItem(
            icon: Symbols.add,
            title: 'Add a bank sender',
            subtitle: 'For a bank sending from a new name',
            onTap: () => addBankSender(context, banks),
          ),
          StreamBuilder<List<String>>(
            stream: getIt<IngestionService>().blocked.watch(),
            builder: (context, snap) {
              final blocked = snap.data ?? const <String>[];
              if (blocked.isEmpty) return const SizedBox.shrink();
              return SettingsItem(
                icon: Symbols.block,
                title: 'Not banks',
                subtitle: 'SMS from ${blocked.join(', ')} is skipped',
                onTap: () => _unblock(context, blocked),
                trailing: const SettingsChevron(),
              );
            },
          ),
        ],
      );
    },
  );

  /// Senders marked "Not a bank" in Review; reading one again lets its
  /// payment-like SMS back into Review.
  Future<void> _unblock(BuildContext context, List<String> blocked) async {
    final core = await showKSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sheetTitle(context, 'Not banks'),
            for (final b in blocked)
              ListTile(
                leading: const Icon(Symbols.sms),
                title: Text(b),
                trailing: TextButton(
                  onPressed: () => Navigator.pop(context, b),
                  child: const Text('Read again'),
                ),
              ),
          ],
        ),
      ),
    );
    if (core == null) return;
    final ingestion = getIt<IngestionService>();
    await ingestion.blocked.remove(core);
    ingestion.invalidate();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SMS from $core will wait in Review')),
      );
    }
  }

  static Widget sheetTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: context.kt.title),
    ),
  );
}

/// Adds an SMS or email sender to a bank (Settings → Banks, 06k).
/// With no [bank], asks which bank first.
Future<void> addBankSender(
  BuildContext context,
  List<BankView> banks, {
  BankView? bank,
}) async {
  BankView? picked = bank;
  if (picked == null) {
    final id = await showBankPicker(
      context,
      banks: banks,
      title: 'Which bank?',
      allowNew: false,
    );
    picked = banks.where((x) => x.id == id).firstOrNull;
  }
  if (picked == null || !context.mounted) return;
  final b = picked;
  final channel = await showKSheet<Channel>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BankSettings.sheetTitle(context, 'Add a ${b.name} sender'),
          ListTile(
            leading: const Icon(Symbols.sms),
            title: const Text('SMS sender'),
            subtitle: const Text('The middle of the header, e.g. AXISBK'),
            onTap: () => Navigator.pop(context, Channel.sms),
          ),
          ListTile(
            leading: const Icon(Symbols.mail),
            title: const Text('Email sender'),
            subtitle: const Text('An address or domain, e.g. axis.bank.in'),
            onTap: () => Navigator.pop(context, Channel.email),
          ),
        ],
      ),
    ),
  );
  if (channel == null || !context.mounted) return;
  final sms = channel == Channel.sms;
  final pattern = await promptText(
    context,
    title: sms ? 'SMS sender' : 'Email sender',
    hint: sms ? 'e.g. AXISBK' : 'e.g. alerts@axis.bank.in',
    help: sms
        ? 'From a header like AX-AXISBK-S, enter AXISBK.'
        : 'A full address, or a domain to read all its mail.',
    action: 'Add',
  );
  if (pattern == null || pattern.trim().isEmpty) return;
  await getIt<BankRepository>().addSender(b.id, channel, pattern);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('k now reads ${pattern.trim()} as ${b.name}')),
    );
  }
}
