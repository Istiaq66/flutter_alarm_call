package io.github.istiaq66.flutter_alarm_call

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * The native half of flutter_alarm_call: puts the host activity over the lock
 * screen when an alarm call launches it, and ends the call screen.
 *
 * Scheduling and ringing are flutter_local_notifications'. What it cannot do
 * is show the activity over the keyguard the moment the call's full-screen
 * intent arrives — waiting for Dart to boot would leave the call screen
 * behind the lock screen while the alarm is already ringing — or take down a
 * posted notification without also deleting its schedule.
 */
class FlutterAlarmCallPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null

    private val activity: Activity?
        get() = activityBinding?.activity

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // Runs inside the host activity's onCreate, early enough for the
    // lock-screen flags to apply to the first frame.
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        showOverLockScreenIfAlarmCall(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() = detachFromActivity()

    private fun detachFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    // Not consumed: flutter_local_notifications reads the same intent to
    // report the response to Dart.
    override fun onNewIntent(intent: Intent): Boolean {
        showOverLockScreenIfAlarmCall(intent)
        return false
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
            "endCall" -> {
                endCall(
                    notificationId = call.argument<Int>("notificationId"),
                    unlock = call.argument<Boolean>("unlock") == true,
                )
                result.success(null)
            }
            "releaseLockScreen" -> {
                setOverLockScreen(false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun showOverLockScreenIfAlarmCall(intent: Intent?) {
        val payload = intent?.getStringExtra(PAYLOAD_EXTRA) ?: return
        if (payload.startsWith(PAYLOAD_PREFIX)) setOverLockScreen(true)
    }

    /**
     * Cancels only the posted notification. flutter_local_notifications' own
     * cancel also drops the schedule, which for a daily call would silence
     * every day after this one.
     */
    private fun endCall(notificationId: Int?, unlock: Boolean) {
        if (notificationId != null) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(notificationId)
        }
        setOverLockScreen(false)
        val current = activity ?: return
        if (unlock) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                keyguard.requestDismissKeyguard(current, null)
            }
        } else {
            current.moveTaskToBack(true)
        }
    }

    private fun setOverLockScreen(enabled: Boolean) {
        val current = activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            current.setShowWhenLocked(enabled)
            current.setTurnScreenOn(enabled)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enabled) current.window.addFlags(flags) else current.window.clearFlags(flags)
        }
    }

    /**
     * Android 14 gates full-screen intents behind a per-app switch that is off
     * by default for apps the platform does not treat as alarm or calling
     * apps; without it the call is only a heads-up notification.
     */
    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.canUseFullScreenIntent()
    }

    private companion object {
        const val CHANNEL = "flutter_alarm_call"

        /** flutter_local_notifications puts a notification's payload under this extra. */
        const val PAYLOAD_EXTRA = "payload"

        /** Must match `alarmCallPayloadPrefix` on the Dart side. */
        const val PAYLOAD_PREFIX = "flutter_alarm_call:"
    }
}
