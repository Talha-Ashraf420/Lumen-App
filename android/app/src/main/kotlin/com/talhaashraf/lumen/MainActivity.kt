package com.talhaashraf.lumen

import android.content.Intent
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "lumen/pip"
    private val media3ChannelName = "lumen/media3"
    private val deviceChannelName = "lumen/device"
    private var pipAllowed = false
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPipAllowed" -> {
                    pipAllowed = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "enterPip" -> result.success(enterPip())
                "isSupported" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            media3ChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(true)
                "open" -> {
                    val args = call.arguments as? Map<*, *>
                    val url = args?.get("url") as? String
                    if (url.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val headers = HashMap<String, String>()
                    (args["headers"] as? Map<*, *>)?.forEach { (key, value) ->
                        if (key is String && value is String) headers[key] = value
                    }
                    val intent = Intent(this, Media3PlayerActivity::class.java).apply {
                        putExtra(Media3PlayerActivity.EXTRA_URL, url)
                        putExtra(
                            Media3PlayerActivity.EXTRA_TITLE,
                            args["title"] as? String ?: ""
                        )
                        putExtra(
                            Media3PlayerActivity.EXTRA_IS_LIVE,
                            args["isLive"] as? Boolean ?: false
                        )
                        putExtra(Media3PlayerActivity.EXTRA_HEADERS, headers)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTelevision" -> result.success(isTelevision())
                else -> result.notImplemented()
            }
        }
    }

    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val televisionMode =
            uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        val leanback =
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP &&
                    packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY))
        // Some non-certified Android TVs omit Leanback declarations. A large
        // Android device without a touchscreen is still overwhelmingly likely
        // to be a television and should receive the low-memory experience.
        val remoteOnlyLargeScreen =
            !packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN) &&
                resources.configuration.smallestScreenWidthDp >= 600
        return televisionMode || leanback || remoteOnlyLargeScreen
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

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
