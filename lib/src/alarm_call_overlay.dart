import 'package:flutter/material.dart';

import 'alarm_call.dart';
import 'flutter_alarm_call_service.dart';

/// Builds a custom call screen for [call]. Wire the buttons to
/// [FlutterAlarmCall.answer] and [FlutterAlarmCall.dismiss].
typedef AlarmCallScreenBuilder = Widget Function(
  BuildContext context,
  ActiveAlarmCall call,
);

/// Lays the call screen over [child] while a call is ringing.
///
/// Put it in `MaterialApp.builder`, so it covers every route — including a
/// splash screen on a cold launch — and the app underneath carries on:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => AlarmCallOverlay(child: child!),
/// )
/// ```
class AlarmCallOverlay extends StatelessWidget {
  /// Wraps [child]; [screenBuilder] replaces the default [AlarmCallScreen].
  const AlarmCallOverlay({super.key, required this.child, this.screenBuilder});

  /// The app.
  final Widget child;

  /// Builds the call screen, or null for [AlarmCallScreen].
  final AlarmCallScreenBuilder? screenBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveAlarmCall?>(
      valueListenable: FlutterAlarmCall.activeCall,
      child: child,
      builder: (context, call, child) => Stack(
        children: [
          child!,
          if (call != null)
            Positioned.fill(
              child: screenBuilder?.call(context, call) ??
                  AlarmCallScreen(call: call),
            ),
        ],
      ),
    );
  }
}

/// The default call screen: caller, body, and dismiss / answer buttons on
/// the call's color.
class AlarmCallScreen extends StatelessWidget {
  /// Shows [call]. [icon] sits above the caller's name.
  const AlarmCallScreen({
    super.key,
    required this.call,
    this.icon = Icons.alarm_rounded,
  });

  /// The ringing call.
  final ActiveAlarmCall call;

  /// Shown above the caller's name.
  final IconData icon;

  static const _answerColor = Color(0xFF2E9E5B);
  static const _dismissColor = Color(0xFFC0392B);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = call.body;

    return Material(
      color: call.color,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            children: [
              const Spacer(),
              Icon(icon, size: 72, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                call.callerName,
                textAlign: TextAlign.center,
                style: textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(color: Colors.white70),
                ),
              ],
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    color: _dismissColor,
                    icon: Icons.close_rounded,
                    label: call.dismissLabel,
                    onPressed: FlutterAlarmCall.dismiss,
                  ),
                  _CallButton(
                    color: _answerColor,
                    icon: Icons.call_rounded,
                    label: call.answerLabel,
                    onPressed: FlutterAlarmCall.answer,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: RawMaterialButton(
            onPressed: onPressed,
            fillColor: color,
            shape: const CircleBorder(),
            constraints: const BoxConstraints.tightFor(width: 72, height: 72),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}
