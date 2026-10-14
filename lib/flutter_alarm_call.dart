/// Rings like an incoming call at a scheduled time, even when the app is
/// closed. See [FlutterAlarmCall] to schedule, and [AlarmCallOverlay] for the
/// call screen.
library;

export 'src/alarm_call.dart' show ActiveAlarmCall, AlarmCall, AlarmCallChannel;
export 'src/alarm_call_overlay.dart'
    show AlarmCallOverlay, AlarmCallScreen, AlarmCallScreenBuilder;
export 'src/alarm_call_platform.dart'
    show AlarmCallPlatform, MethodChannelAlarmCallPlatform;
export 'src/flutter_alarm_call_service.dart' show FlutterAlarmCall;
