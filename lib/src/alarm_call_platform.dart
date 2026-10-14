import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The native calls flutter_alarm_call makes beyond
/// flutter_local_notifications. Replaceable in tests.
abstract class AlarmCallPlatform extends PlatformInterface {
  /// Constructs the platform interface.
  AlarmCallPlatform() : super(token: _token);

  static final Object _token = Object();

  static AlarmCallPlatform _instance = MethodChannelAlarmCallPlatform();

  /// The implementation in use.
  static AlarmCallPlatform get instance => _instance;

  /// Swaps the implementation, for tests.
  static set instance(AlarmCallPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether Android lets full-screen intents take over the screen.
  Future<bool> canUseFullScreenIntent();

  /// Takes down notification [notificationId] without touching its schedule,
  /// drops the lock-screen override, then unlocks or backgrounds the app.
  Future<void> endCall({required int notificationId, required bool unlock});

  /// Drops the lock-screen override without ending anything.
  Future<void> releaseLockScreen();
}

/// [AlarmCallPlatform] over the plugin's method channel.
class MethodChannelAlarmCallPlatform extends AlarmCallPlatform {
  /// The channel the Kotlin plugin listens on.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_alarm_call');

  @override
  Future<bool> canUseFullScreenIntent() async =>
      await methodChannel.invokeMethod<bool>('canUseFullScreenIntent') ?? false;

  @override
  Future<void> endCall({required int notificationId, required bool unlock}) =>
      methodChannel.invokeMethod<void>('endCall', {
        'notificationId': notificationId,
        'unlock': unlock,
      });

  @override
  Future<void> releaseLockScreen() =>
      methodChannel.invokeMethod<void>('releaseLockScreen');
}
