package com.talhaashraf.lumen

import android.content.Intent
import android.app.Activity
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.provider.OpenableColumns
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "lumen/pip"
    private val media3ChannelName = "lumen/media3"
    private val deviceChannelName = "lumen/device"
    private val subtitleChannelName = "lumen/subtitles"
    private val subtitleRequestCode = 6204
    private var pipAllowed = false
    private var methodChannel: MethodChannel? = null
    private var pendingSubtitleResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPipAllowed" -> {
                    pipAllowed = !isTelevision() &&
                        (call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                "enterPip" -> result.success(!isTelevision() && enterPip())
                "isSupported" -> result.success(
                    !isTelevision() &&
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
                    val playlistUrls = ArrayList<String>()
                    val playlistTitles = ArrayList<String>()
                    (args["playlist"] as? List<*>)?.forEach { rawItem ->
                        val item = rawItem as? Map<*, *> ?: return@forEach
                        val itemUrl = item["url"] as? String
                        if (!itemUrl.isNullOrBlank()) {
                            playlistUrls.add(itemUrl)
                            playlistTitles.add(item["title"] as? String ?: "")
                        }
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
                        putStringArrayListExtra(
                            Media3PlayerActivity.EXTRA_PLAYLIST_URLS,
                            playlistUrls
                        )
                        putStringArrayListExtra(
                            Media3PlayerActivity.EXTRA_PLAYLIST_TITLES,
                            playlistTitles
                        )
                        putExtra(
                            Media3PlayerActivity.EXTRA_INITIAL_INDEX,
                            (args["initialIndex"] as? Number)?.toInt() ?: 0
                        )
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
                "displaySize" -> {
                    val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        // Android TV may render its launcher and apps at 1080p
                        // even while driving a 4K panel. The largest supported
                        // mode reveals the real panel class more reliably than
                        // only inspecting the currently selected mode.
                        display?.supportedModes?.maxByOrNull {
                            it.physicalWidth.toLong() * it.physicalHeight.toLong()
                        } ?: display?.mode
                    } else {
                        null
                    }
                    val metrics = resources.displayMetrics
                    result.success(
                        mapOf(
                            "width" to (mode?.physicalWidth ?: metrics.widthPixels),
                            "height" to (mode?.physicalHeight ?: metrics.heightPixels)
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            subtitleChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pickSubtitleFile(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickSubtitleFile(result: MethodChannel.Result) {
        if (pendingSubtitleResult != null) {
            result.error("picker_busy", "A subtitle picker is already open.", null)
            return
        }
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/x-subrip",
                    "text/srt",
                    "text/vtt",
                    "text/plain",
                    "text/x-ssa",
                    "text/x-ass",
                    "application/ttml+xml"
                )
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        pendingSubtitleResult = result
        try {
            startActivityForResult(picker, subtitleRequestCode)
        } catch (error: Exception) {
            pendingSubtitleResult = null
            result.error(
                "picker_unavailable",
                "No file browser is available on this device.",
                error.message
            )
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != subtitleRequestCode) return
        val result = pendingSubtitleResult ?: return
        pendingSubtitleResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val flags = (data?.flags ?: 0) and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (flags != 0) {
                contentResolver.takePersistableUriPermission(uri, flags)
            }
        } catch (_: SecurityException) {
            // The temporary grant is enough for the immediate import.
        }
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("The selected subtitle could not be read.")
            if (bytes.size > 5 * 1024 * 1024) {
                throw IllegalArgumentException("Subtitle files must be smaller than 5 MB.")
            }
            var displayName = "External subtitle"
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    displayName = cursor.getString(0) ?: displayName
                }
            }
            result.success(
                mapOf(
                    "name" to displayName,
                    "data" to String(bytes, Charsets.UTF_8).removePrefix("\uFEFF"),
                    "mimeType" to (contentResolver.getType(uri) ?: "text/plain")
                )
            )
        } catch (error: Exception) {
            result.error("subtitle_read_failed", error.message, null)
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
        if (isTelevision()) return false
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
        if (pipAllowed && !isTelevision()) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
