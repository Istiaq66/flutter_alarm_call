import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// Prefix of every alarm call's notification payload.
///
/// The Android side matches it to put the app over the lock screen, so it
/// must not change without changing `FlutterAlarmCallPlugin.kt` too.
const alarmCallPayloadPrefix = 'flutter_alarm_call:';

/// The notification channel alarm calls ring on.
///
/// Android fixes a channel's sound, vibration and audio usage the first time
/// it is created; changing any of them later needs a new [id].
@immutable
class AlarmCallChannel {
  /// Creates a channel description.
  const AlarmCallChannel({
    this.id = 'flutter_alarm_call',
    this.name = 'Alarm calls',
    this.description,
    this.rawSound,
    this.vibrationPattern = const [0, 800, 600, 800],
  });

  /// Channel id. Change it to change the sound or vibration of an existing
  /// install.
  final String id;

  /// Name shown in the system's notification settings.
  final String name;

  /// Description shown in the system's notification settings.
  final String? description;

  /// Name of a sound in `android/app/src/main/res/raw`, without extension,
  /// or null for the device's default alarm sound.
  ///
  /// Resource shrinking cannot see a sound referenced by name; keep it with
  /// `res/raw/keep.xml` (see the README) or release builds lose it.
  final String? rawSound;

  /// Vibration pattern in milliseconds: off, on, off, on…
  final List<int> vibrationPattern;
}

/// One call to ring at [time].
@immutable
class AlarmCall {
  /// Describes a call. Only [id], [callerName] and [time] are required.
  const AlarmCall({
    required this.id,
    required this.callerName,
    required this.time,
    this.body,
    this.repeatDaily = false,
    this.ringDuration = const Duration(seconds: 45),
    this.answerLabel = 'Answer',
    this.dismissLabel = 'Dismiss',
    this.color = const Color(0xFF0F5233),
    this.channel = const AlarmCallChannel(),
  });

  /// Notification id. Scheduling again with the same id replaces the call.
  final int id;

  /// Who the call appears to be from: the notification title and the name on
  /// the call screen.
  final String callerName;

  /// When to ring. Must be in the future.
  final DateTime time;

  /// Line under the caller's name.
  final String? body;

  /// Ring again at the same time of day, every day, without the app running.
  final bool repeatDaily;

  /// How long the call rings before it gives up.
  final Duration ringDuration;

  /// Label of the button that answers: stops the ring and opens the app.
  final String answerLabel;

  /// Label of the button that stops the ring and leaves the app closed.
  final String dismissLabel;

  /// Accent of the notification, and background of the default call screen.
  final Color color;

  /// The channel to ring on.
  final AlarmCallChannel channel;
}

/// The call currently ringing, as the call screen shows it.
@immutable
class ActiveAlarmCall {
  /// Creates the description of a ringing call.
  const ActiveAlarmCall({
    required this.id,
    required this.callerName,
    this.body,
    this.answerLabel = 'Answer',
    this.dismissLabel = 'Dismiss',
    this.color = const Color(0xFF0F5233),
  });

  /// Rebuilds a ringing call from its notification payload, or returns null
  /// for any payload that is not an alarm call's.
  static ActiveAlarmCall? fromPayload(int id, String? payload) {
    if (payload == null || !payload.startsWith(alarmCallPayloadPrefix)) {
      return null;
    }
    try {
      final json = jsonDecode(payload.substring(alarmCallPayloadPrefix.length))
          as Map<String, dynamic>;
      return ActiveAlarmCall(
        id: id,
        callerName: json['caller'] as String? ?? '',
        body: json['body'] as String?,
        answerLabel: json['answer'] as String? ?? 'Answer',
        dismissLabel: json['dismiss'] as String? ?? 'Dismiss',
        color: Color(json['color'] as int? ?? 0xFF0F5233),
      );
    } on FormatException {
      return ActiveAlarmCall(id: id, callerName: '');
    } on TypeError {
      return ActiveAlarmCall(id: id, callerName: '');
    }
  }

  /// The payload carrying [call] to the call screen. A notification's
  /// buttons and text cannot be read back once posted, so what the screen
  /// shows travels here.
  static String payloadFor(AlarmCall call) {
    return alarmCallPayloadPrefix +
        jsonEncode({
          'caller': call.callerName,
          if (call.body != null) 'body': call.body,
          'answer': call.answerLabel,
          'dismiss': call.dismissLabel,
          'color': call.color.toARGB32(),
        });
  }

  /// Notification id of the ringing call.
  final int id;

  /// Who the call appears to be from.
  final String callerName;

  /// Line under the caller's name.
  final String? body;

  /// Label of the answer button.
  final String answerLabel;

  /// Label of the dismiss button.
  final String dismissLabel;

  /// Background of the default call screen.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is ActiveAlarmCall &&
      other.id == id &&
      other.callerName == callerName &&
      other.body == body &&
      other.answerLabel == answerLabel &&
      other.dismissLabel == dismissLabel &&
      other.color == color;

  @override
  int get hashCode =>
      Object.hash(id, callerName, body, answerLabel, dismissLabel, color);
}
