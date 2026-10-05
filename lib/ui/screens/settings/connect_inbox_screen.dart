import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../data/email/email_source.dart';
import '../../../data/email/email_sync.dart';
import '../../../data/email/google_auth.dart';
import '../../../di.dart';
import '../../../platform/sms_bridge.dart';
import '../../format.dart';
import '../../theme/k_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/date_pick.dart';

/// Google sign-in → Gmail read access → inbox saved and read from [since].
/// Shows the outcome in a snackbar; true when the inbox is connected.
Future<bool> connectGoogle(BuildContext context, DateTime since) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String s) => messenger.showSnackBar(SnackBar(content: Text(s)));
  try {
    final email = await getIt<GoogleAuth>().signIn();
    final logged = await getIt<EmailSync>().addGoogle(
      email: email,
      since: since,
    );
    await getIt<SmsBridge>().scheduleEmailSync(on: true);
    say(
      logged == 0
          ? 'Connected $email. No new payments in the mail.'
          : 'Connected $email. $logged new '
                '${logged == 1 ? 'payment' : 'payments'} logged.',
    );
    return true;
  } on GoogleSignInException catch (e) {
    if (e.code != GoogleSignInExceptionCode.canceled) {
      say("Google sign-in didn't finish. Try again.");
    }
  } on EmailAuthException {
    say("Google didn't give k access to Gmail. Allow it when asked.");
  } catch (_) {
    say("Couldn't reach Gmail. Check the connection.");
  }
  return false;
}

/// Pick how k reads mail (design 06b).
class ConnectInboxScreen extends StatefulWidget {
  const ConnectInboxScreen({super.key});

  @override
  State<ConnectInboxScreen> createState() => _ConnectInboxScreenState();
}

class _ConnectInboxScreenState extends State<ConnectInboxScreen> {
  late DateTime _since = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }();
  bool _signingIn = false;

  Future<void> _google() async {
    setState(() => _signingIn = true);
    final ok = await connectGoogle(context, _since);
    if (!mounted) return;
    setState(() => _signingIn = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Connect an inbox'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            "k reads only your banks' alert mail, on this phone. "
            'Nothing leaves it.',
            style: t.body.copyWith(color: c.text2, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _Option(
            icon: Icons.account_circle_outlined,
            title: 'Sign in with Google',
            tag: 'Recommended',
            subtitle:
                "Read-only. If Google says k isn't verified, tap "
                'Advanced → Go to k.',
            busy: _signingIn,
            onTap: _signingIn ? null : _google,
          ),
          const SizedBox(height: 16),
          _Option(
            icon: Icons.key_outlined,
            title: 'Use an app password',
            subtitle: 'For Gmail with 2-Step Verification, or other IMAP mail',
            onTap: () async {
              final done = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AppPasswordScreen(since: _since),
                ),
              );
              if (done == true && context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: 16),
          FieldRow(
            label: 'Read past mail from',
            onTap: () async {
              final d = await pickImportStart(context, initial: _since);
              if (d != null) setState(() => _since = d);
            },
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fullDay(_since),
                  style: t.body.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 16, color: c.text2),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Checked hourly and when k opens.',
            style: t.meta.copyWith(color: c.text3, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tag,
    this.busy = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? tag;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    return Opacity(
      opacity: onTap == null && !busy ? 0.5 : 1,
      child: Material(
        color: c.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: c.text2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: t.body.copyWith(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (tag != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: c.text3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tag!,
                                style: t.label.copyWith(
                                  fontSize: 11.5,
                                  color: c.text2,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: t.meta.copyWith(fontSize: 13, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                busy
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.text2,
                        ),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: c.text3,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gmail address + app password (design 06c). With [email] set it replaces
/// the password of an inbox already connected.
class AppPasswordScreen extends StatefulWidget {
  const AppPasswordScreen({super.key, this.email, this.since});

  final String? email;
  final DateTime? since;

  @override
  State<AppPasswordScreen> createState() => _AppPasswordScreenState();
}

class _AppPasswordScreenState extends State<AppPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _password = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final t = context.kt;
    InputDecoration box(String hint) => InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.outline),
      ),
    );
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        s,
        style: t.meta.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('App password'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          label('Gmail address'),
          TextField(
            controller: _email,
            enabled: widget.email == null,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: box('you@gmail.com'),
          ),
          const SizedBox(height: 20),
          label('App password'),
          TextField(
            controller: _password,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: box('16 letters, spaces are fine').copyWith(
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
                  'Get one from Google',
                  style: t.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final (i, s) in const [
                  'Turn on 2-Step Verification for your Google account.',
                  'Open myaccount.google.com/apppasswords.',
                  'Create one named k and paste the 16 letters here.',
                ].indexed) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${i + 1}',
                        style: t.amountRow.copyWith(
                          fontSize: 14,
                          color: c.text3,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s, style: t.meta.copyWith(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'The password stays in secure storage on this phone.',
            style: t.meta.copyWith(color: c.text3, height: 1.35),
          ),
        ],
      ),
      bottomNavigationBar: Container(
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
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.bg),
                )
              : const Icon(Icons.link_rounded, size: 20),
          label: Text(_busy ? 'Connecting…' : 'Connect'),
        ),
      ),
    );
  }

  Future<void> _connect() async {
    final email = _email.text.trim();
    final password = _password.text.trim();
    if (!email.contains('@') || password.isEmpty) {
      setState(() => _error = 'Enter the address and the app password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final logged = await getIt<EmailSync>().addImap(
        email: email,
        appPassword: password,
        since: widget.since ?? DateTime(now.year, now.month),
      );
      await getIt<SmsBridge>().scheduleEmailSync(on: true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            logged == 0
                ? 'Connected. No new payments in the mail.'
                : 'Connected. $logged ${logged == 1 ? 'payment' : 'payments'} logged.',
          ),
        ),
      );
    } on EmailAuthException {
      setState(
        () => _error =
            'Google refused it. Check the address and use an app password, '
            'not your Google password.',
      );
    } catch (_) {
      setState(() => _error = "Couldn't reach Gmail. Check the connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
