import 'package:flutter/services.dart';

/// Native side of in-app updates (`k/update`, `UpdateChannel.kt`).
class UpdateBridge {
  static const _channel = MethodChannel('k/update');

  /// Installed versionName ("1.0.0") and versionCode (10000).
  Future<({String name, int code})> appVersion() async {
    final m = await _channel.invokeMapMethod<String, Object?>('appVersion');
    return (name: m!['name']! as String, code: (m['code']! as num).toInt());
  }

  /// "Install unknown apps" allowed for k (Android 8+ asks per app).
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  /// Hands the APK to the system installer; Android asks to confirm.
  Future<void> install(String path) =>
      _channel.invokeMethod<void>('install', {'path': path});
}
