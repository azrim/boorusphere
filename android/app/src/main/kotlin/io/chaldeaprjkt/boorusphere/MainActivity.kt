package io.chaldeaprjkt.boorusphere

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity, not FlutterActivity: the biometric prompt is a
// fragment, and it cannot be shown from a plain activity.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        AppEnv.setUp(flutterEngine.dartExecutor.binaryMessenger, AndroidAppEnv())
        StorageUtil.setUp(flutterEngine.dartExecutor.binaryMessenger, AndroidStorageUtil(this))
        SecureScreen.setUp(flutterEngine.dartExecutor.binaryMessenger, this)
        VolumeKeys.setUp(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (VolumeKeys.handleKeyDown(keyCode)) return true
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (VolumeKeys.handleKeyUp(keyCode)) return true
        return super.onKeyUp(keyCode, event)
    }
}
