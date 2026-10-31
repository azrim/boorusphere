package io.chaldeaprjkt.boorusphere

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
    }
}
