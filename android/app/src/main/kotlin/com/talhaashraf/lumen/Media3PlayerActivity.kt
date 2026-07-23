package com.talhaashraf.lumen

import android.app.Activity
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.ui.PlayerView

/**
 * Full-screen native fallback for provider streams that libmpv cannot open.
 *
 * Media3 owns decoding, buffering, track selection and TV remote controls.
 * Automatic recovery is bounded; the user always retains an explicit Retry
 * and Android Back exits immediately.
 */
@OptIn(UnstableApi::class)
class Media3PlayerActivity : Activity() {
    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_IS_LIVE = "isLive"
        const val EXTRA_HEADERS = "headers"

        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 60_000
        private val RETRY_DELAYS_MS = longArrayOf(1_000, 3_000, 5_000)
    }

    private lateinit var player: ExoPlayer
    private lateinit var playerView: PlayerView
    private lateinit var errorPanel: LinearLayout
    private lateinit var errorText: TextView
    private lateinit var retryButton: Button
    private val handler = Handler(Looper.getMainLooper())
    private var retryAttempt = 0
    private var retryScheduled = false
    private var url = ""
    private var isLive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        url = intent.getStringExtra(EXTRA_URL).orEmpty()
        isLive = intent.getBooleanExtra(EXTRA_IS_LIVE, false)
        if (url.isBlank()) {
            finish()
            return
        }

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            keepScreenOn = true
        }
        playerView = PlayerView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
            setShowSubtitleButton(true)
            controllerShowTimeoutMs = 2_500
            isFocusable = true
        }
        root.addView(playerView)
        root.addView(buildTitleBar())
        errorPanel = buildErrorPanel()
        root.addView(errorPanel)
        setContentView(root)

        player = buildPlayer()
        playerView.player = player
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_READY -> {
                        retryAttempt = 0
                        retryScheduled = false
                        errorPanel.visibility = View.GONE
                    }
                    Player.STATE_ENDED -> if (isLive) scheduleRetry(
                        "The live feed ended. Reconnecting…"
                    )
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                scheduleRetry(friendlyError(error))
            }
        })
        open()
    }

    private fun buildPlayer(): ExoPlayer {
        @Suppress("DEPRECATION")
        val supplied = intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<*, *>
        val headers = HashMap<String, String>()
        supplied?.forEach { (key, value) ->
            if (key is String && value is String) headers[key] = value
        }
        val userAgent = headers.remove("User-Agent") ?: "Lumen/1.1 Android"
        val http = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(CONNECT_TIMEOUT_MS)
            .setReadTimeoutMs(READ_TIMEOUT_MS)
            .setUserAgent(userAgent)
            .setDefaultRequestProperties(headers)

        // Live keeps a responsive window; VOD builds a deeper cushion to absorb
        // Wi-Fi/provider jitter before playback and after an underrun.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                if (isLive) 15_000 else 30_000,
                if (isLive) 35_000 else 60_000,
                if (isLive) 4_000 else 8_000,
                if (isLive) 6_000 else 10_000
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(http)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(3))
        return ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
            .build()
    }

    private fun buildTitleBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), dp(12), dp(18), dp(12))
            setBackgroundColor(0x99000000.toInt())
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }
        val back = Button(this).apply {
            text = "‹"
            textSize = 28f
            contentDescription = "Back to Lumen"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.TRANSPARENT)
            setOnClickListener { finish() }
        }
        val title = TextView(this).apply {
            text = intent.getStringExtra(EXTRA_TITLE).orEmpty()
            textSize = 16f
            setTextColor(Color.WHITE)
            maxLines = 1
            layoutParams = LinearLayout.LayoutParams(0, dp(48), 1f)
            gravity = Gravity.CENTER_VERTICAL
        }
        bar.addView(back, LinearLayout.LayoutParams(dp(54), dp(48)))
        bar.addView(title)
        return bar
    }

    private fun buildErrorPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            setPadding(dp(28), dp(24), dp(28), dp(24))
            setBackgroundColor(0xEE111315.toInt())
            layoutParams = FrameLayout.LayoutParams(
                dp(390),
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        }
        errorText = TextView(this).apply {
            textSize = 15f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, dp(16))
        }
        retryButton = Button(this).apply {
            text = "Try again"
            isFocusable = true
            setOnClickListener {
                retryAttempt = 0
                retryScheduled = false
                errorPanel.visibility = View.GONE
                open()
            }
        }
        panel.addView(
            errorText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        panel.addView(retryButton, LinearLayout.LayoutParams(dp(180), dp(52)))
        return panel
    }

    private fun open() {
        player.setMediaItem(MediaItem.fromUri(Uri.parse(url)))
        player.playWhenReady = true
        player.prepare()
    }

    private fun scheduleRetry(message: String) {
        if (retryScheduled) return
        if (retryAttempt >= RETRY_DELAYS_MS.size) {
            showError(message)
            return
        }
        retryScheduled = true
        val delay = RETRY_DELAYS_MS[retryAttempt++]
        errorText.text = "$message\nRetrying ${retryAttempt}/${RETRY_DELAYS_MS.size}…"
        errorPanel.visibility = View.VISIBLE
        handler.postDelayed({
            retryScheduled = false
            errorPanel.visibility = View.GONE
            open()
        }, delay)
    }

    private fun showError(message: String) {
        errorText.text = message
        errorPanel.visibility = View.VISIBLE
        retryButton.requestFocus()
    }

    private fun friendlyError(error: PlaybackException): String = when {
        error.errorCodeName.contains("HTTP", ignoreCase = true) ->
            "The provider rejected or could not serve this stream."
        error.errorCodeName.contains("DECOD", ignoreCase = true) ->
            "Android cannot decode this stream format."
        else -> "The stream did not start in the compatibility player."
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (
            event.action == KeyEvent.ACTION_DOWN &&
            event.keyCode in listOf(
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER
            ) &&
            !playerView.isControllerFullyVisible
        ) {
            playerView.showController()
            playerView.requestFocus()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (::player.isInitialized) {
            playerView.player = null
            player.release()
        }
        super.onDestroy()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
