package io.chaldeaprjkt.boorusphere

import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards the hardware volume keys to the post viewer while it is on screen.
 *
 * Volume keys never reach a Flutter widget on Android: the framework turns
 * them into a volume change before the key event is offered to the view. The
 * activity therefore owns the key and only consumes it while Dart has asked
 * for it, so everywhere else the buttons still change the volume.
 */
object VolumeKeys {
    private const val channelName = "io.chaldeaprjkt.boorusphere/volume_keys"

    private var channel: MethodChannel? = null
    private var enabled = false

    fun setUp(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, channelName).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        enabled = call.argument<Boolean>("enabled") ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** Returns true when the viewer claimed this key and it must not change the volume. */
    fun handleKeyDown(keyCode: Int): Boolean {
        if (!enabled || !isVolumeKey(keyCode)) return false

        channel?.invokeMethod(
            "onVolumeKey",
            if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down",
        )
        return true
    }

    /** Swallow the matching key-up as well, so nothing leaks to the volume panel. */
    fun handleKeyUp(keyCode: Int): Boolean = enabled && isVolumeKey(keyCode)

    private fun isVolumeKey(keyCode: Int): Boolean =
        keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
}
