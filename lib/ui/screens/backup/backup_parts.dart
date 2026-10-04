import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../data/backup/backup_service.dart';
import '../../../data/backup/drive_client.dart';
import '../../../di.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import 'passphrase_screen.dart';

/// Outlined text field in the 06c/06f style.
InputDecoration fieldBox(BuildContext context, String hint) {
  final c = context.k;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: c.outline),
  );
  return InputDecoration(hintText: hint, border: border, enabledBorder: border);
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: context.kt.meta.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// Bottom action bar with one full-width primary button.
class BottomAction extends StatelessWidget {
  const BottomAction({
    super.key,
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        border: Border(top: BorderSide(color: c.outline)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.bg),
              )
            : Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

/// Settings → Backup switch on: passphrase (first time), Google account
/// for Drive, then a first backup. False when the owner backed out.
Future<bool> turnOnBackup(BuildContext context) async {
  final backup = getIt<BackupService>();
  final messenger = ScaffoldMessenger.of(context);
  if (!await backup.hasPassphrase) {
    if (!context.mounted) return false;
    final set = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PassphraseScreen()));
    if (set != true) return false;
  }
  try {
    await backup.connectDrive();
  } on GoogleSignInException catch (e) {
    if (e.code != GoogleSignInExceptionCode.canceled) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't sign in to Google")),
      );
    }
    return false;
  }
  messenger.showSnackBar(const SnackBar(content: Text('Backing up…')));
  await backUpNow(messenger);
  return true;
}

Future<void> backUpNow(ScaffoldMessengerState messenger) async {
  try {
    await getIt<BackupService>().backupNow();
    messenger.showSnackBar(const SnackBar(content: Text('Backed up to Drive')));
  } on DriveAuthException {
    messenger.showSnackBar(
      const SnackBar(content: Text('Google refused access. Sign in again.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Backup didn't finish. k tries again tonight."),
      ),
    );
  }
}

/// "03:02 today" / "yesterday, 03:01" / "3 Oct, 03:04".
String whenShort(DateTime at) {
  final today = dateOnly(DateTime.now());
  final day = dateOnly(at);
  if (day == today) return '${hhmm(at)} today';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'yesterday, ${hhmm(at)}';
  }
  return '${dayMonth(at)}, ${hhmm(at)}';
}

String sizeShort(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
