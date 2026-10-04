import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import '../data/repositories/settings_repository.dart';

/// App lock (design 07): when on, k opens behind the lock screen and asks
/// Android's BiometricPrompt (fingerprint or the phone's screen lock).
/// Locks on a cold start and after [grace] away, so a quick trip to a
/// share sheet or Google sign-in doesn't lock.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock(this._settings, {required bool enabled, LocalAuthentication? auth})
    : _enabled = enabled,
      _locked = enabled,
      _auth = auth ?? LocalAuthentication() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const grace = Duration(minutes: 1);

  final SettingsRepository _settings;
  final LocalAuthentication _auth;

  bool _enabled;
  bool _locked;
  bool _authenticating = false;
  DateTime? _awaySince;

  bool get enabled => _enabled;
  bool get locked => _locked;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The PIN fallback is its own activity: k pauses while it's up.
    if (!_enabled || _authenticating) return;
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _awaySince ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _awaySince;
        _awaySince = null;
        if (since != null && DateTime.now().difference(since) >= grace) {
          _setLocked(true);
        }
      default:
    }
  }

  /// Asks the system prompt. The lock screen plays the drawn moment, then
  /// calls [release]. A phone with no screen lock left can't lock k
  /// ([UnlockResult.unavailable]), so it opens rather than staying stuck.
  Future<UnlockResult> unlock() =>
      _prompt('Use your fingerprint or screen lock');

  void release() => _setLocked(false);

  /// Turning on asks once, so the owner knows the prompt works here.
  Future<UnlockResult> enable() async {
    final r = await _prompt('Confirm to turn on app lock');
    if (r == UnlockResult.ok) {
      _enabled = true;
      await _settings.set(SettingsRepository.appLock, 'true');
      notifyListeners();
    }
    return r;
  }

  Future<void> disable() async {
    _enabled = false;
    _locked = false;
    await _settings.set(SettingsRepository.appLock, 'false');
    notifyListeners();
  }

  Future<UnlockResult> _prompt(String hint) async {
    if (_authenticating) return UnlockResult.failed;
    _authenticating = true;
    try {
      if (!await _auth.isDeviceSupported()) return UnlockResult.unavailable;
      final ok = await _auth.authenticate(
        localizedReason: hint,
        authMessages: [
          AndroidAuthMessages(signInTitle: 'Unlock k', signInHint: hint),
        ],
        persistAcrossBackgrounding: true,
      );
      return ok ? UnlockResult.ok : UnlockResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet => UnlockResult.unavailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => UnlockResult.lockedOut,
        _ => UnlockResult.failed,
      };
    } finally {
      _authenticating = false;
      _awaySince = null;
    }
  }

  void _setLocked(bool v) {
    if (_locked == v) return;
    _locked = v;
    notifyListeners();
  }
}

enum UnlockResult {
  ok,
  failed,

  /// Too many tries; Android asks again later.
  lockedOut,

  /// No fingerprint or screen lock set on the phone.
  unavailable,
}
