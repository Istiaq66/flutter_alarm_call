import 'package:flutter/material.dart';
import 'package:flutter_alarm_call/flutter_alarm_call.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform extends AlarmCallPlatform {
  final ended = <({int id, bool unlock})>[];
  int releases = 0;

  @override
  Future<bool> canUseFullScreenIntent() async => true;

  @override
  Future<void> endCall({
    required int notificationId,
    required bool unlock,
  }) async =>
      ended.add((id: notificationId, unlock: unlock));

  @override
  Future<void> releaseLockScreen() async => releases++;
}

AlarmCall _call({
  int id = 7,
  String? rawSound,
  DateTime? time,
}) =>
    AlarmCall(
      id: id,
      callerName: 'Namaz',
      body: 'Time for Fajr',
      time: time ?? DateTime(2030, 1, 1, 5),
      answerLabel: 'Wake up',
      dismissLabel: 'Later',
      color: const Color(0xFF123456),
      channel: AlarmCallChannel(rawSound: rawSound),
    );

NotificationResponse _response(int id, String? payload, {String? actionId}) =>
    NotificationResponse(
      notificationResponseType: actionId == null
          ? NotificationResponseType.selectedNotification
          : NotificationResponseType.selectedNotificationAction,
      id: id,
      actionId: actionId,
      payload: payload,
    );

void main() {
  late _FakePlatform platform;
  var ringing = <int>{};

  setUp(() {
    platform = _FakePlatform();
    AlarmCallPlatform.instance = platform;
    ringing = {};
    FlutterAlarmCall.debugIsSupported = true;
    FlutterAlarmCall.debugActiveNotifications = () async => [
          for (final id in ringing) ActiveNotification(id: id),
        ];
  });

  tearDown(FlutterAlarmCall.debugReset);

  group('payload', () {
    test('carries what the call screen shows', () {
      final payload = ActiveAlarmCall.payloadFor(_call());

      expect(
        ActiveAlarmCall.fromPayload(7, payload),
        const ActiveAlarmCall(
          id: 7,
          callerName: 'Namaz',
          body: 'Time for Fajr',
          answerLabel: 'Wake up',
          dismissLabel: 'Later',
          color: Color(0xFF123456),
        ),
      );
    });

    test('is not claimed for other notifications', () {
      expect(ActiveAlarmCall.fromPayload(7, 'fajr_reminder'), isNull);
      expect(ActiveAlarmCall.fromPayload(7, null), isNull);
    });

    test('a mangled payload still yields a call to end', () {
      final call = ActiveAlarmCall.fromPayload(7, 'flutter_alarm_call:{oops');

      expect(call?.id, 7);
    });
  });

  group('nextOccurrence', () {
    final at = DateTime(2030, 1, 1, 5);

    test('keeps a time still ahead', () {
      expect(
        FlutterAlarmCall.nextOccurrence(at, now: DateTime(2030, 1, 1, 4)),
        at,
      );
    });

    test('rolls a passed time over to tomorrow', () {
      expect(
        FlutterAlarmCall.nextOccurrence(at, now: at),
        DateTime(2030, 1, 2, 5),
      );
    });
  });

  group('the notification', () {
    test('rings like an alarm until answered or timed out', () {
      final details = FlutterAlarmCall.buildAndroidDetails(_call());

      expect(details.fullScreenIntent, isTrue);
      expect(details.audioAttributesUsage, AudioAttributesUsage.alarm);
      expect(details.category, AndroidNotificationCategory.alarm);
      expect(details.additionalFlags, contains(4)); // FLAG_INSISTENT
      expect(details.timeoutAfter, 45000);
      expect(
        details.actions?.map((a) => a.title),
        ['Later', 'Wake up'],
      );
    });

    test('falls back to the device alarm sound', () {
      final details = FlutterAlarmCall.buildAndroidDetails(_call());

      expect(details.sound, isA<UriAndroidNotificationSound>());
    });

    test('plays an app sound when given one', () {
      final details =
          FlutterAlarmCall.buildAndroidDetails(_call(rawSound: 'bird'));

      expect(
        (details.sound! as RawResourceAndroidNotificationSound).sound,
        'bird',
      );
    });
  });

  test('refuses a time that has passed', () {
    expect(
      () => FlutterAlarmCall.schedule(
        _call(time: DateTime(2020)),
        now: DateTime(2030),
      ),
      throwsArgumentError,
    );
  });

  group('responses', () {
    final payload = ActiveAlarmCall.payloadFor(_call());

    test('the full-screen intent shows the call while it rings', () async {
      ringing = {7};

      expect(FlutterAlarmCall.handleNotificationResponse(_response(7, payload)),
          isTrue);
      await pumpEventQueue();

      expect(FlutterAlarmCall.activeCall.value?.callerName, 'Namaz');
    });

    test('a launch after the ring ended releases the lock screen', () async {
      FlutterAlarmCall.handleNotificationResponse(_response(7, payload));
      await pumpEventQueue();

      expect(FlutterAlarmCall.activeCall.value, isNull);
      expect(platform.releases, 1);
    });

    test('the answer button ends the call and unlocks', () async {
      FlutterAlarmCall.handleNotificationResponse(
        _response(7, payload, actionId: 'flutter_alarm_call_answer'),
      );
      await pumpEventQueue();

      expect(platform.ended, [(id: 7, unlock: true)]);
    });

    test('other notifications are left to the app', () {
      expect(
        FlutterAlarmCall.handleNotificationResponse(_response(3, 'reminder')),
        isFalse,
      );
    });

    test('off Android nothing is claimed', () {
      FlutterAlarmCall.debugIsSupported = false;

      expect(FlutterAlarmCall.handleNotificationResponse(_response(7, payload)),
          isFalse);
    });
  });

  group('AlarmCallOverlay', () {
    Future<void> ring(WidgetTester tester) async {
      ringing = {7};
      FlutterAlarmCall.handleNotificationResponse(
        _response(7, ActiveAlarmCall.payloadFor(_call())),
      );
      await tester.pump();
    }

    /// Lets the ring time out, so no watch timer outlives the test.
    Future<void> endRing(WidgetTester tester) async {
      ringing = {};
      await tester.pump(const Duration(seconds: 2));
    }

    Widget app() => MaterialApp(
          builder: (context, child) => AlarmCallOverlay(child: child!),
          home: const Text('home'),
        );

    testWidgets('covers the app while a call rings', (tester) async {
      await tester.pumpWidget(app());
      expect(find.text('Namaz'), findsNothing);

      await ring(tester);

      expect(find.text('Namaz'), findsOneWidget);
      expect(find.text('Time for Fajr'), findsOneWidget);
      await endRing(tester);
    });

    testWidgets('closes once the ring times out', (tester) async {
      await tester.pumpWidget(app());
      await ring(tester);

      await endRing(tester);

      expect(find.text('Namaz'), findsNothing);
      expect(platform.releases, 1);
    });

    testWidgets('dismiss ends the call and backgrounds the app',
        (tester) async {
      await tester.pumpWidget(app());
      await ring(tester);

      await tester.tap(find.bySemanticsLabel('Later'));
      await tester.pump();

      expect(platform.ended, [(id: 7, unlock: false)]);
      expect(find.text('Namaz'), findsNothing);
    });

    testWidgets('takes a custom screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => AlarmCallOverlay(
          screenBuilder: (context, call) => Text('custom ${call.callerName}'),
          child: child!,
        ),
        home: const Text('home'),
      ));
      await ring(tester);

      expect(find.text('custom Namaz'), findsOneWidget);
      await endRing(tester);
    });
  });
}
