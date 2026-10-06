import 'package:flutter/material.dart';

import '../../../data/backup/backup_file.dart';
import '../../../data/backup/backup_service.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import 'backup_parts.dart';

/// Restore (design 06g): what the backup holds, its passphrase (skipped when
/// this phone's saved key already opens it), and a confirm before
/// everything is replaced.
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key, required this.file, required this.source});

  final BackupFile file;

  /// "from Drive" / "from a file".
  final String source;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  final _passphrase = TextEditingController();
  final _backup = getIt<BackupService>();
  bool? _savedKeyOpens;
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _backup.opensWithSavedKey(widget.file).then((v) {
      if (mounted) setState(() => _savedKeyOpens = v);
    });
  }

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final needs = _savedKeyOpens != true;
    if (needs && _passphrase.text.isEmpty) {
      setState(() => _error = 'Enter the passphrase this backup was made with');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything?'),
        content: const Text(
          "Everything on this phone is replaced with the backup's. This can't "
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _backup.restore(
        widget.file,
        passphrase: needs ? _passphrase.text : null,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${widget.file.header.meta.payments} payments',
          ),
        ),
      );
    } on BackupKeyException {
      setState(() => _error = "That passphrase doesn't open this backup");
    } on FormatException catch (e) {
      setState(() => _error = "Can't restore: ${e.message}");
    } catch (e) {
      setState(() => _error = "Restore didn't finish: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    final m = widget.file.header.meta;
    Widget row(String l, String v) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(child: Text(l, style: t.meta)),
          Text(v, style: t.amountRow),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Restore'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
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
                  '${_cap(whenShort(m.createdAt))} · ${widget.source}',
                  style: t.body.copyWith(fontWeight: FontWeight.w600),
                ),
                row('Payments', grouped(m.payments)),
                row('Accounts', '${m.accounts}'),
                row('Subscriptions', '${m.subscriptions}'),
                row('Learned formats', '${m.formats}'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_savedKeyOpens == false) ...[
            const FieldLabel('Passphrase for this backup'),
            TextField(
              controller: _passphrase,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              decoration: fieldBox(context, 'The one you set for backups')
                  .copyWith(
                    suffixIcon: IconButton(
                      tooltip: _show ? 'Hide' : 'Show',
                      icon: Icon(
                        _show
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
              onSubmitted: (_) => _restore(),
            ),
            const SizedBox(height: 20),
          ] else if (_savedKeyOpens == true) ...[
            Text('Opens with your current passphrase.', style: t.meta),
            const SizedBox(height: 20),
          ],
          if (_error != null) ...[
            Text(_error!, style: t.meta.copyWith(color: c.alert)),
            const SizedBox(height: 12),
          ],
          Text(
            "Restoring replaces everything on this phone. Email inboxes need "
            'signing in again.',
            style: t.meta.copyWith(height: 1.35),
          ),
        ],
      ),
      bottomNavigationBar: BottomAction(
        icon: Icons.settings_backup_restore_rounded,
        label: _busy ? 'Restoring…' : 'Restore',
        busy: _busy || _savedKeyOpens == null,
        onPressed: _restore,
      ),
    );
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
}
