import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'alarm_call.dart';
import 'alarm_call_platform.dart';

/// Schedules alarm calls and tracks the one ringing.
///
/// A call is a flutter_local_notifications notification scheduled as an alarm
/// clock: when it fires, the system posts it, rings on the alarm stream until
/// it is answered or [AlarmCall.ringDuration] passes, and raises the app over
/// the lock screen through its full-screen intent. No Dart runs at ring time,
/// which is the point: plugins that wake a background isolate go through
/// JobScheduler, and OEM builds (vivo, Xiaomi, Oppo…) hold those jobs while
/// the app is closed, so the call only rings once the user opens the app.
///
/// Android only; every method is a no-op elsewhere.
///
/// The app owns flutter_local_notifications' `initialize` and its single
/// response callback, so it forwards responses here with
/// [handleNotificationResponse], and calls [restoreFromLaunch] at startup.
class FlutterAlarmCall {
  FlutterAlarmCall._();

  static const _flagInsistent = 4; // Notification.FLAG_INSISTENT
  static const _defaultAlarmSound = 'content://settings/system/alarm_alert';
  static const _answerActionId = 'flutter_alarm_call_answer';
  static const _dismissActionId = 'flutter_alarm_call_dismiss';
  static const _pollInterval = Duration(seconds: 2);

  static final _activeCall = ValueNotifier<ActiveAlarmCall?>(null);
  static Timer? _watch;

  /// Overrides the platform check, for tests.
  @visibleForTesting
  static bool? debugIsSupported;

  /// Replaces the active-notification lookup, for tests.
  @visibleForTesting
  static Future<List<ActiveNotification>> Function()? debugActiveNotifications;

  static bool get _isSupported =>
      debugIsSupported ?? (!kIsWeb && Platform.isAndroid);

  static FlutterLocalNotificationsPlugin get _notifications =>
      FlutterLocalNotificationsPlugin();

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// The call ringing right now, or null. Drives `AlarmCallOverlay`.
  static ValueListenable<ActiveAlarmCall?> get activeCall => _activeCall;

  /// The next time [time] comes round: [time] itself while it is ahead,
  /// otherwise the same time a day later.
  static DateTime nextOccurrence(DateTime time, {DateTime? now}) {
    final current = now ?? DateTime.now();
    return time.isAfter(current) ? time : time.add(const Duration(days: 1));
  }

  /// Schedules [call], replacing any call with the same id.
  ///
  /// Returns false without scheduling when exact alarms are not allowed
  /// (Android 12+; see [requestExactAlarmPermission]) or off Android. Throws
  /// [ArgumentError] when [AlarmCall.time] is not in the future.
  ///
  /// The time zone comes from `tz.local`. Without the app setting it (see the
  /// README) it is UTC: the call still rings at the right instant, but a
  /// daily repeat ignores daylight-saving changes.
  static Future<bool> schedule(AlarmCall call, {DateTime? now}) async {
    if (!call.time.isAfter(now ?? DateTime.now())) {
      throw ArgumentError.value(
          call.time, 'call.time', 'must be in the future');
    }
    if (!_isSupported) return false;
    if (!await canScheduleExactAlarms()) return false;

    await _notifications.zonedSchedule(
      call.id,
      call.callerName,
      call.body,
      tz.TZDateTime.from(call.time, tz.local),
      NotificationDetails(android: buildAndroidDetails(call)),
      // Exempt from Doze and app standby, and exact to the minute.
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      matchDateTimeComponents:
          call.repeatDaily ? DateTimeComponents.time : null,
      payload: ActiveAlarmCall.payloadFor(call),
    );
    return true;
  }

  /// The notification [call] rings as.
  @visibleForTesting
  static AndroidNotificationDetails buildAndroidDetails(AlarmCall call) {
    final channel = call.channel;
    final sound = channel.rawSound;
    return AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      sound: sound == null
          ? const UriAndroidNotificationSound(_defaultAlarmSound)
          : RawResourceAndroidNotificationSound(sound),
      // The alarm stream rings through silent mode, like the clock app.
      audioAttributesUsage: AudioAttributesUsage.alarm,
      vibrationPattern: Int64List.fromList(channel.vibrationPattern),
      // Loop the sound until the notification goes, instead of once.
      additionalFlags: Int32List.fromList([_flagInsistent]),
      timeoutAfter: call.ringDuration.inMilliseconds,
      ongoing: true,
      autoCancel: false,
      color: call.color,
      actions: [
        // Both take down only the posted notification, natively; a daily
        // schedule stays.
        AndroidNotificationAction(_dismissActionId, call.dismissLabel),
        AndroidNotificationAction(
          _answerActionId,
          call.answerLabel,
          showsUserInterface: true,
        ),
      ],
    );
  }

  /// Cancels call [id]: its schedule and, if it is ringing, the ring.
  static Future<void> cancel(int id) async {
    if (!_isSupported) return;
    if (_activeCall.value?.id == id) _stopWatching();
    await _notifications.cancel(id);
  }

  /// Picks up a call that launched the app from cold: its full-screen intent,
  /// a tap on the notification, or its answer button. Call it early in
  /// `main`, so the call screen does not wait on the rest of startup.
  static Future<void> restoreFromLaunch() async {
    if (!_isSupported) return;
    final details = await _notifications.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if ((details?.didNotificationLaunchApp ?? false) && response != null) {
      handleNotificationResponse(response);
    }
  }

  /// Routes a response from flutter_local_notifications' callback. Returns
  /// false for notifications that are not alarm calls, so the app can handle
  /// those itself.
  static bool handleNotificationResponse(NotificationResponse response) {
    if (!_isSupported) return false;
    final id = response.id;
    final call =
        id == null ? null : ActiveAlarmCall.fromPayload(id, response.payload);
    if (call == null) return false;

    switch (response.actionId) {
      case _answerActionId:
        unawaited(_end(call.id, unlock: true));
      case _dismissActionId:
        unawaited(_end(call.id, unlock: false));
      default:
        // The full-screen intent, or a tap on the notification body.
        unawaited(_showWhileRinging(call));
    }
    return true;
  }

  /// Answers the ringing call: stops the ring and leaves the user in the
  /// app, asking them to unlock.
  static Future<void> answer() async {
    final call = _activeCall.value;
    if (call != null) await _end(call.id, unlock: true);
  }

  /// Dismisses the ringing call: stops the ring and sends the app to the
  /// background.
  static Future<void> dismiss() async {
    final call = _activeCall.value;
    if (call != null) await _end(call.id, unlock: false);
  }

  static Future<void> _end(int id, {required bool unlock}) async {
    _stopWatching();
    await AlarmCallPlatform.instance
        .endCall(notificationId: id, unlock: unlock);
  }

  /// Shows the call screen for as long as the notification is up. A launch
  /// that arrives after the ring timed out drops the lock-screen override
  /// instead, so the app does not sit over the keyguard.
  static Future<void> _showWhileRinging(ActiveAlarmCall call) async {
    if (!await _isRinging(call.id)) {
      await AlarmCallPlatform.instance.releaseLockScreen();
      return;
    }
    _activeCall.value = call;
    _watch?.cancel();
    _watch = Timer.periodic(_pollInterval, (_) async {
      if (await _isRinging(call.id)) return;
      _stopWatching();
      await AlarmCallPlatform.instance.releaseLockScreen();
    });
  }

  static void _stopWatching() {
    _watch?.cancel();
    _watch = null;
    _activeCall.value = null;
  }

  static Future<bool> _isRinging(int id) async {
    final lookup =
        debugActiveNotifications ?? _notifications.getActiveNotifications;
    final active = await lookup();
    return active.any((n) => n.id == id);
  }

  /// Whether exact alarms are allowed. Always true below Android 12.
  static Future<bool> canScheduleExactAlarms() async {
    if (!_isSupported) return false;
    return await _android?.canScheduleExactNotifications() ?? false;
  }

  /// Opens the system "Alarms & reminders" page for the app.
  static Future<void> requestExactAlarmPermission() async {
    if (!_isSupported) return;
    await _android?.requestExactAlarmsPermission();
  }

  /// Whether the call may take over the screen. Android 14 turns this off by
  /// default for apps it does not treat as alarm or calling apps; without it
  /// the call is a heads-up notification that still rings.
  static Future<bool> canUseFullScreenIntent() async {
    if (!_isSupported) return false;
    return AlarmCallPlatform.instance.canUseFullScreenIntent();
  }

  /// Opens the system page where full-screen notifications are allowed.
  static Future<void> requestFullScreenIntentPermission() async {
    if (!_isSupported) return;
    await _android?.requestFullScreenIntentPermission();
  }

  /// Whether the app may post notifications at all.
  static Future<bool> canPostNotifications() async {
    if (!_isSupported) return false;
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Asks for the notification permission (Android 13+).
  static Future<bool> requestNotificationPermission() async {
    if (!_isSupported) return false;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// Clears the ringing state and test overrides, for tests.
  @visibleForTesting
  static void debugReset() {
    _stopWatching();
    debugIsSupported = null;
    debugActiveNotifications = null;
  }
}
