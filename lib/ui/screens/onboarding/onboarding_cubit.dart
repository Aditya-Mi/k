import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/ingest/sms_sync.dart';
import '../../../data/repositories/settings_repository.dart';

/// How far back the first run reads the inbox.
enum HistoryRange {
  none('None', null),
  days30('30 days', 30),
  days90('90 days', 90),
  year('1 year', 365);

  const HistoryRange(this.label, this.days);
  final String label;
  final int? days;
}

class OnboardingState extends Equatable {
  const OnboardingState({
    this.sms,
    this.battery,
    this.history = HistoryRange.days90,
    this.importing = false,
    this.logged = 0,
    this.done = false,
    this.error,
  });

  final PermissionStatus? sms;
  final PermissionStatus? battery;
  final HistoryRange history;
  final bool importing;
  final int logged;
  final bool done;
  final String? error;

  bool get smsGranted => sms?.isGranted ?? false;

  /// Sideloaded on Android 13+: the system blocks the prompt outright until
  /// "Allow restricted settings" is turned on in App info.
  bool get smsBlocked => sms?.isPermanentlyDenied ?? false;

  OnboardingState copyWith({
    PermissionStatus? sms,
    PermissionStatus? battery,
    HistoryRange? history,
    bool? importing,
    int? logged,
    bool? done,
    String? Function()? error,
  }) => OnboardingState(
    sms: sms ?? this.sms,
    battery: battery ?? this.battery,
    history: history ?? this.history,
    importing: importing ?? this.importing,
    logged: logged ?? this.logged,
    done: done ?? this.done,
    error: error != null ? error() : this.error,
  );

  @override
  List<Object?> get props => [
    sms,
    battery,
    history,
    importing,
    logged,
    done,
    error,
  ];
}

class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit(this._sync, this._settings) : super(const OnboardingState());

  final SmsSync _sync;
  final SettingsRepository _settings;

  Future<void> refresh() async {
    final sms = await Permission.sms.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    if (!isClosed) emit(state.copyWith(sms: sms, battery: battery));
  }

  Future<void> requestSms() async {
    final sms = await Permission.sms.request();
    emit(state.copyWith(sms: sms));
  }

  Future<void> requestBattery() async {
    final battery = await Permission.ignoreBatteryOptimizations.request();
    emit(state.copyWith(battery: battery));
  }

  Future<void> openAppInfo() => openAppSettings();

  void chooseHistory(HistoryRange h) => emit(state.copyWith(history: h));

  Future<void> finish() async {
    if (!state.smsGranted || state.importing) return;
    emit(state.copyWith(importing: true, logged: 0, error: () => null));
    try {
      final days = state.history.days;
      final since = days == null
          ? null
          : DateTime.now().subtract(Duration(days: days));
      final logged = await _sync.importHistory(
        since,
        onProgress: (n) {
          if (!isClosed) emit(state.copyWith(logged: n));
        },
      );
      await _settings.set(SettingsRepository.onboardingDone, 'true');
      emit(state.copyWith(importing: false, logged: logged, done: true));
    } catch (e) {
      emit(
        state.copyWith(
          importing: false,
          error: () => 'Could not read messages: $e',
        ),
      );
    }
  }
}
