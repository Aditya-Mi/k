import 'package:flutter/material.dart';
import 'package:txn_parser/txn_parser.dart' show Channel;

import '../../../data/repositories/bank_repository.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import '../../widgets/text_prompt.dart';
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsHead('Banks'),
          for (final b in banks)
            SettingsItem(
              icon: Icons.account_balance_outlined,
              title: b.name,
              subtitle: _senders(b),
              onTap: () => _addSender(context, banks, bank: b),
              trailing: const SettingsChevron(),
            ),
          SettingsItem(
            icon: Icons.add_rounded,
            title: 'Add a bank sender',
            subtitle: 'When a bank texts or mails from a new name',
            onTap: () => _addSender(context, banks),
          ),
        ],
      );
    },
  );

  static String _senders(BankView b) => [
    if (b.sms.isNotEmpty) 'SMS from ${b.sms.join(', ')}',
    if (b.email.isNotEmpty) 'email from ${b.email.join(', ')}',
    if (b.sms.isEmpty && b.email.isEmpty) 'No senders',
  ].join(' · ');

  Future<void> _addSender(
    BuildContext context,
    List<BankView> banks, {
    BankView? bank,
  }) async {
    final b =
        bank ??
        await showModalBottomSheet<BankView>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _sheetTitle(context, 'Which bank?'),
                for (final b in banks)
                  ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: Text(b.name),
                    onTap: () => Navigator.pop(context, b),
                  ),
              ],
            ),
          ),
        );
    if (b == null || !context.mounted) return;
    final channel = await showModalBottomSheet<Channel>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTitle(context, 'Add a ${b.name} sender'),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('SMS sender'),
              subtitle: const Text('The middle of the header, e.g. AXISBK'),
              onTap: () => Navigator.pop(context, Channel.sms),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline_rounded),
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

  static Widget _sheetTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: context.kt.title),
    ),
  );
}
