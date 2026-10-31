package io.chaldeaprjkt.boorusphere

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Toggles FLAG_SECURE, which keeps the window out of screenshots and out of
 * the recents preview.
 *
 * The flag is a window property, so it has to be set from the activity rather
 * than by the Dart layer. A window flag cannot be read back, so the Dart side
 * keeps the preference and sends the wanted state.
 */
object SecureScreen {
    private const val channel = "io.chaldeaprjkt.boorusphere/secure"

    fun setUp(messenger: BinaryMessenger, activity: FlutterFragmentActivity) {
        MethodChannel(messenger, channel).setMethodCallHandler { call, result ->
            if (call.method != "setFlagSecure") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val enabled = call.argument<Boolean>("enabled") ?: false
            activity.runOnUiThread {
                if (enabled) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
            }
            result.success(null)
        }
    }
}
