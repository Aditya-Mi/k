import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'gmail_source.dart';

/// Google sign-in for Gmail (read-only). The Web client ID is the token
/// audience Credential Manager needs; the Android client (package + SHA-1)
/// is matched by Google and never named here. Neither is a secret.
class GoogleAuth {
  static const webClientId =
      '392394428908-0r9v89fum5v45fsk7fqjipfh8ag1kld4.apps.googleusercontent.com';
  static const gmailScope = 'https://www.googleapis.com/auth/gmail.readonly';

  /// Drive backups: only files k itself created.
  static const driveScope = 'https://www.googleapis.com/auth/drive.file';

  Future<void>? _init;

  Future<void> _ready() =>
      _init ??= GoogleSignIn.instance.initialize(serverClientId: webClientId);

  /// Interactive: pick an account and grant [scope] (Gmail read by
  /// default). Returns the address. Throws [GoogleSignInException] (code
  /// `canceled` when backed out).
  Future<String> signIn({String scope = gmailScope}) async {
    await _ready();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: [scope],
    );
    await account.authorizationClient.authorizeScopes([scope]);
    return account.email.toLowerCase();
  }

  /// Access token for [email] without any UI (works in the background
  /// worker); null when the owner has to sign in again.
  Future<String?> token(String email, {String scope = gmailScope}) async {
    await _ready();
    final tokens = await GoogleSignInPlatform.instance
        .clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters(
            request: AuthorizationRequestDetails(
              scopes: [scope],
              userId: null,
              email: email,
              promptIfUnauthorized: false,
            ),
          ),
        );
    return tokens?.accessToken;
  }

  /// Drops a token Google rejected so the next [token] call fetches a new one.
  Future<void> forget(String accessToken) =>
      GoogleSignInPlatform.instance.clearAuthorizationToken(
        ClearAuthorizationTokenParams(accessToken: accessToken),
      );

  /// Revokes k's access (last Google inbox disconnected).
  Future<void> disconnect() async {
    await _ready();
    await GoogleSignIn.instance.disconnect();
  }

  GmailSource gmail(String email) =>
      GmailSource(accessToken: () => token(email), dropToken: forget);
}
