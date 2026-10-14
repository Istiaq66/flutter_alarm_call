# flutter_alarm_call

Rings like an incoming call at a scheduled time — even when the app is closed,
the phone is locked, or the device is on a battery-hungry OEM build.

- Exact alarm-clock timing, exempt from Doze and app standby
- Loops a sound on the **alarm stream** (rings through silent mode) until
  answered or timed out
- Full-screen **call screen over the lock screen**, default or your own
- Answer / dismiss from the notification or the call screen
- Once or **daily**, without the app running

Android only. On other platforms every call is a no-op (iOS apps can only show
a call screen from a server-sent VoIP push).

## Why another one

Plugins that ring by waking a background Dart isolate
(`android_alarm_manager_plus` and the like) hand the alarm to JobScheduler.
vivo, Xiaomi, Oppo and other OEM builds hold those jobs while the app is
closed, so the "call" rings only once the user opens the app — which, for a
wake-up call, is never.

Here **no Dart runs at ring time**. The call is a
[flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)
notification scheduled with `setAlarmClock`: the system posts it, plays the
sound and fires its full-screen intent on its own. This plugin's native side
only puts your activity over the keyguard the instant it launches and ends the
call without deleting a daily schedule.

## Install

```yaml
dependencies:
  flutter_alarm_call: ^0.1.0
  flutter_local_notifications: ^19.4.2
```

`flutter_local_notifications` needs core library desugaring in
`android/app/build.gradle.kts`:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
```

No manifest edits: the plugin declares its permissions
(`SCHEDULE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `POST_NOTIFICATIONS`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`) and flutter_local_notifications'
scheduling, action and boot receivers.

> **Play policy:** `SCHEDULE_EXACT_ALARM` and `USE_FULL_SCREEN_INTENT` are
> restricted permissions. Declare the alarm/calling use in the Play Console
> when you submit.

## Use

### 1. Wire it up at startup

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // First: a launch by the call's full-screen intent shows the call screen
  // before the rest of startup.
  unawaited(FlutterAlarmCall.restoreFromLaunch());

  // Local time zone, so daily calls follow daylight saving (optional — see
  // "Time zones").
  tz.initializeTimeZones();
  tz.setLocalLocation(
    tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
  );

  // You own flutter_local_notifications' initialize; forward responses.
  await FlutterLocalNotificationsPlugin().initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (response) {
      if (FlutterAlarmCall.handleNotificationResponse(response)) return;
      // …your other notifications
    },
  );

  runApp(const MyApp());
}
```

### 2. Add the call screen

```dart
MaterialApp(
  builder: (context, child) => AlarmCallOverlay(child: child!),
  home: const HomePage(),
);
```

It covers every route while a call rings and closes itself when the ring
times out or is dismissed from the notification shade. For your own design:

```dart
AlarmCallOverlay(
  screenBuilder: (context, call) => MyCallScreen(
    caller: call.callerName,
    onAnswer: FlutterAlarmCall.answer,
    onDismiss: FlutterAlarmCall.dismiss,
  ),
  child: child!,
)
```

### 3. Ask for permissions

```dart
await FlutterAlarmCall.requestNotificationPermission();      // Android 13+
if (!await FlutterAlarmCall.canScheduleExactAlarms()) {
  await FlutterAlarmCall.requestExactAlarmPermission();       // "Alarms & reminders"
}
if (!await FlutterAlarmCall.canUseFullScreenIntent()) {
  await FlutterAlarmCall.requestFullScreenIntentPermission(); // Android 14+
}
```

The last two open system settings pages; re-check them when the app resumes.
Without exact alarms nothing is scheduled (`schedule` returns `false`).
Without full-screen intents the call still rings, as a heads-up notification.

### 4. Schedule

```dart
await FlutterAlarmCall.schedule(
  AlarmCall(
    id: 1,
    callerName: 'Wake-up call',
    body: 'Time to get up',
    time: DateTime.now().add(const Duration(hours: 8)),
    repeatDaily: true,
    answerLabel: "I'm up",
    dismissLabel: 'Dismiss',
    ringDuration: const Duration(seconds: 45),
    channel: const AlarmCallChannel(
      id: 'wake_up_calls',
      name: 'Wake-up calls',
      rawSound: 'rooster', // android/app/src/main/res/raw/rooster.mp3
    ),
  ),
);

await FlutterAlarmCall.cancel(1);
```

Scheduling the same `id` again replaces the call — handy for times that drift
day to day (prayer times, sunrise): reschedule whenever the app or a
background task runs, and the daily repeat covers the days it does not.

## Gotchas

**Custom sounds and release builds.** Resource shrinking cannot see a sound
referenced by name and strips it from release builds. Keep it with
`android/app/src/main/res/raw/keep.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@raw/rooster" />
```

**Channels are fixed on first use.** Android locks a channel's sound and
vibration when it is created. To change them on existing installs, use a new
`AlarmCallChannel.id`.

**Time zones.** Times go through `tz.local`. If the app never sets it, it is
UTC: a call still rings at the right instant, but a daily repeat ignores
daylight-saving changes.

**Force stop.** "Force stop" in system settings (and, on some OEM builds,
swiping the app from recents) deletes every alarm the app has set; that is
Android's rule, not something a plugin can work around. The next
`schedule` re-arms it.

**Your activity shows over the lock screen** only while a call launched it, and
stops as soon as the call is answered, dismissed or times out. Answering asks
the user to unlock.

## Example

[`example/`](example/lib/main.dart) shows permissions, a 15-second test call and
a daily call.
