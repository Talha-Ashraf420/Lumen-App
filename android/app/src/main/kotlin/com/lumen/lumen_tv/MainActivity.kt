package com.lumen.lumen_tv

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "lumen/pip"
    private var pipAllowed = false
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                // Flutter tells us whether a video is currently active, so we
                // only enter PiP when there's something worth keeping on screen.
                "setPipAllowed" -> {
                    pipAllowed = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                // Explicit request (e.g. a PiP button) — enter immediately.
                "enterPip" -> result.success(enterPip())
                "isSupported" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (e: Exception) {
            false
        }
    }

    // Fires when the user presses Home / Recents while the app is foreground.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Let Flutter hide the chrome and show video-only while in PiP.
        methodChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
