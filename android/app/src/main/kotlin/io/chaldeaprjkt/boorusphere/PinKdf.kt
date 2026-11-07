package io.chaldeaprjkt.boorusphere

import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

object PinKdf {
    private const val channelName = "io.chaldeaprjkt.boorusphere/pin_kdf"

    fun setUp(messenger: BinaryMessenger) {
        MethodChannel(
            messenger,
            channelName,
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method != "derive" || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val arguments = call.arguments as? Map<*, *>
            val pin = arguments?.get("pin") as? String
            val salt = arguments?.get("salt") as? ByteArray
            val iterations = arguments?.get("iterations") as? Int
            if (pin == null || salt == null || salt.isEmpty() ||
                iterations == null || iterations <= 0
            ) {
                result.error("invalid_arguments", "Invalid derivation arguments.", null)
                return@setMethodCallHandler
            }

            val key = try {
                derive(pin, salt, iterations)
            } catch (_: Exception) {
                result.error("kdf_failed", "PIN derivation failed.", null)
                return@setMethodCallHandler
            }
            result.success(key)
        }
    }

    private fun derive(pin: String, salt: ByteArray, iterations: Int): ByteArray {
        // Do not normalize the PIN: existing hashes use its original UTF-8 bytes.
        val password = pin.toCharArray()
        val spec = try {
            PBEKeySpec(password, salt, iterations, 256)
        } finally {
            password.fill('\u0000')
        }
        return try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                .generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
    }
}
