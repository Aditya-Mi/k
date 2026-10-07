import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/backup/backup_service.dart';
import '../../../di.dart';
import '../../theme/k_theme.dart';
import 'backup_parts.dart';

/// Backup passphrase (design 06f): set the first time backup is turned on,
/// or changed from the Backup screen. Pops true once saved.
class PassphraseScreen extends StatefulWidget {
  const PassphraseScreen({
    super.key,
    this.title = 'Backup passphrase',
    this.action = 'Turn on backup',
  });

  final String title;
  final String action;

  @override
  State<PassphraseScreen> createState() => _PassphraseScreenState();
}

class _PassphraseScreenState extends State<PassphraseScreen> {
  final _first = TextEditingController();
  final _again = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _again.dispose();
    super.dispose();
  }

  static bool strongEnough(String p) =>
      p.length >= 12 || p.trim().split(RegExp(r'\s+')).length >= 4;

  Future<void> _save() async {
    final p = _first.text;
    if (!strongEnough(p)) {
      setState(() => _error = 'Use at least 4 words or 12 characters');
      return;
    }
    if (p != _again.text) {
      setState(() => _error = "The two don't match");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await getIt<BackupService>().setPassphrase(p);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't save it. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final eye = IconButton(
      tooltip: _show ? 'Hide' : 'Show',
      icon: Icon(_show ? Symbols.visibility_off : Symbols.visibility),
      onPressed: () => setState(() => _show = !_show),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const FieldLabel('Passphrase'),
          TextField(
            style: context.kt.input,
            controller: _first,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: fieldBox(
              context,
              'A short sentence works',
            ).copyWith(suffixIcon: eye),
          ),
          const SizedBox(height: 20),
          const FieldLabel('Type it again'),
          TextField(
            style: context.kt.input,
            controller: _again,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: fieldBox(context, 'Same passphrase'),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: t.meta.copyWith(color: c.alert)),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface1,
              border: Border.all(color: c.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Pick one you'll remember",
                  style: t.body.copyWith(fontWeight: FontWeight.w600),
                ),
                for (final s in const [
                  'At least 4 words or 12 characters.',
                  'k keeps it on this phone for daily backups.',
                  'On a new phone you type it once to restore.',
                ]) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•', style: t.meta.copyWith(color: c.text3)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s, style: t.meta)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "If you forget it, your backups can't be opened by you, k or "
            'Google. A new one only covers new backups.',
            style: t.meta.copyWith(color: c.alert, height: 1.35),
          ),
        ],
      ),
      bottomNavigationBar: BottomAction(
        icon: Symbols.key,
        label: _busy ? 'Saving…' : widget.action,
        busy: _busy,
        onPressed: _save,
      ),
    );
  }
}
