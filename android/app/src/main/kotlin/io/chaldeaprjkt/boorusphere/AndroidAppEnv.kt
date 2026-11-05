package io.chaldeaprjkt.boorusphere

import AppEnv
import Env
import android.app.Activity
import android.os.Build
import io.chaldeaprjkt.boorusphere.BuildConfig as BuildInfo // make sure that we use proper BuildConfig

class AndroidAppEnv(private val activity: Activity) : AppEnv {
    override fun get(): Env {
        return Env(
            versionName = BuildInfo.VERSION_NAME,
            versionCode = BuildInfo.VERSION_CODE.toLong(),
            sdkVersion = Build.VERSION.SDK_INT.toLong()
        )
    }

    // Finishes the task outright instead of asking for a back press. Back can
    // be refused by the screen that requested the exit, and finishing the
    // activity is what tears the engine down: the next launch builds a new
    // one, whose boot reads the boxes the restore just wrote.
    override fun exitApp() {
        activity.finishAffinity()
    }
}
