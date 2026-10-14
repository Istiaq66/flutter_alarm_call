import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_alarm_call/flutter_alarm_call.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const _callId = 1;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A cold launch by the call's full-screen intent shows the call screen
  // straight away, before anything else at startup.
  unawaited(FlutterAlarmCall.restoreFromLaunch());

  // Local time zone, so a daily call follows daylight-saving changes.
  tz.initializeTimeZones();
  final zone = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(zone.identifier));

  // The app owns flutter_local_notifications' single response callback and
  // forwards alarm-call responses.
  await FlutterLocalNotificationsPlugin().initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (response) {
      if (FlutterAlarmCall.handleNotificationResponse(response)) return;
      // …the app's other notifications.
    },
  );

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_alarm_call',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0F5233)),
      // Covers every route while a call rings.
      builder: (context, child) => AlarmCallOverlay(child: child!),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _notifications = false;
  bool _exactAlarms = false;
  bool _fullScreen = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The permissions are granted on system pages the user leaves the app for.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final notifications = await FlutterAlarmCall.canPostNotifications();
    final exactAlarms = await FlutterAlarmCall.canScheduleExactAlarms();
    final fullScreen = await FlutterAlarmCall.canUseFullScreenIntent();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _exactAlarms = exactAlarms;
      _fullScreen = fullScreen;
    });
  }

  Future<void> _ringIn(Duration delay, {bool daily = false}) async {
    final at = DateTime.now().add(delay);
    final scheduled = await FlutterAlarmCall.schedule(
      AlarmCall(
        id: _callId,
        callerName: 'Wake-up call',
        body: 'Scheduled from the example app',
        time: at,
        repeatDaily: daily,
        answerLabel: "I'm up",
        dismissLabel: 'Dismiss',
      ),
    );
    if (!mounted) return;
    setState(() {
      _status = scheduled
          ? 'Rings at ${TimeOfDay.fromDateTime(at).format(context)}'
              '${daily ? ', then daily' : ''}. Close the app and lock the '
              'phone to see it take over the lock screen.'
          : 'Not scheduled: allow alarms & reminders first.';
    });
  }

  Future<void> _cancel() async {
    await FlutterAlarmCall.cancel(_callId);
    setState(() => _status = 'Cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_alarm_call')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PermissionTile(
            title: 'Notifications',
            granted: _notifications,
            onRequest: () async {
              await FlutterAlarmCall.requestNotificationPermission();
              await _refreshPermissions();
            },
          ),
          _PermissionTile(
            title: 'Alarms & reminders (exact alarms)',
            granted: _exactAlarms,
            onRequest: FlutterAlarmCall.requestExactAlarmPermission,
          ),
          _PermissionTile(
            title: 'Full-screen notifications',
            granted: _fullScreen,
            onRequest: FlutterAlarmCall.requestFullScreenIntentPermission,
          ),
          const Divider(height: 32),
          FilledButton(
            onPressed: () => _ringIn(const Duration(seconds: 15)),
            child: const Text('Ring in 15 seconds'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => _ringIn(const Duration(minutes: 1), daily: true),
            child: const Text('Ring in 1 minute, then daily'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.title,
    required this.granted,
    required this.onRequest,
  });

  final String title;
  final bool granted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        granted ? Icons.check_circle : Icons.error_outline,
        color: granted ? Colors.green : Theme.of(context).colorScheme.error,
      ),
      title: Text(title),
      trailing: granted
          ? null
          : TextButton(onPressed: onRequest, child: const Text('Allow')),
    );
  }
}
