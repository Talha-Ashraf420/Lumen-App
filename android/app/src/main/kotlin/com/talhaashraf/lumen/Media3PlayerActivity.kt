package com.talhaashraf.lumen

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.res.Configuration
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ClipDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.StateListDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView

/**
 * Full-screen native TV player and difficult-stream fallback for Android.
 *
 * Media3 owns decoding and a native SurfaceView; Lumen owns the visible
 * controller and its explicit TV focus graph. Automatic recovery is bounded;
 * the user always retains an explicit Retry and Android Back exits immediately.
 */
@OptIn(UnstableApi::class)
class Media3PlayerActivity : Activity() {
    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_IS_LIVE = "isLive"
        const val EXTRA_PLAYBACK_MODE = "playbackMode"
        const val EXTRA_HEADERS = "headers"
        const val EXTRA_PLAYLIST_URLS = "playlistUrls"
        const val EXTRA_PLAYLIST_ALTERNATE_URLS = "playlistAlternateUrls"
        const val EXTRA_PLAYLIST_TITLES = "playlistTitles"
        const val EXTRA_PLAYLIST_FAVORITE_KEYS = "playlistFavoriteKeys"
        const val EXTRA_PLAYLIST_FAVORITE_STATES = "playlistFavoriteStates"
        const val EXTRA_INITIAL_INDEX = "initialIndex"
        const val EXTRA_LAST_INDEX = "lastIndex"
        const val RESULT_USE_EMBEDDED_ENGINE = Activity.RESULT_FIRST_USER + 20

        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 60_000
        private const val STARTUP_TIMEOUT_MS = 60_000L
        private const val FIRST_VIDEO_FRAME_TIMEOUT_MS = 15_000L
        private const val LIVE_STALL_TIMEOUT_MS = 20_000L
        private const val WATCHDOG_INTERVAL_MS = 2_000L
        private const val CONTROLS_TIMEOUT_MS = 3_000L
        private const val BUFFERING_BADGE_DELAY_MS = 1_200L
        private const val PROGRESS_INTERVAL_MS = 500L
        private const val SEEK_INCREMENT_MS = 10_000L
        private const val SUBTITLE_REQUEST_CODE = 6205
        private val RETRY_DELAYS_MS = longArrayOf(1_000, 3_000, 5_000)
    }

    private lateinit var player: ExoPlayer
    private lateinit var playerView: PlayerView
    private lateinit var titleBar: View
    private lateinit var controlsBar: View
    private lateinit var backButton: TextView
    private lateinit var titleText: TextView
    private lateinit var titleSubtitleText: TextView
    private lateinit var centerTransport: LinearLayout
    private lateinit var previousButton: ImageButton
    private lateinit var nextButton: ImageButton
    private lateinit var rewindButton: ImageButton
    private lateinit var playPauseButton: ImageButton
    private lateinit var forwardButton: ImageButton
    private lateinit var playlistButton: TextView
    private lateinit var subtitleButton: TextView
    private lateinit var audioButton: TextView
    private lateinit var qualityButton: TextView
    private lateinit var moreButton: TextView
    private lateinit var progressBar: SeekBar
    private lateinit var positionText: TextView
    private lateinit var durationText: TextView
    private lateinit var bufferedText: TextView
    private lateinit var bufferingBadge: TextView
    private lateinit var seekFeedback: TextView
    private lateinit var errorPanel: LinearLayout
    private lateinit var errorText: TextView
    private lateinit var errorPreviousButton: TextView
    private lateinit var retryButton: TextView
    private lateinit var errorNextButton: TextView
    private val handler = Handler(Looper.getMainLooper())
    private var retryAttempt = 0
    private var retryScheduled = false
    private var terminalError = false
    private var url = ""
    private var isLive = false
    private var playbackMode = Media3PlaybackMode.BALANCED
    private var playlistUrls = listOf<String>()
    private var playlistAlternateUrls = listOf<String>()
    private var playlistTitles = listOf<String>()
    private var playlistFavoriteKeys = listOf<String>()
    private var playlistFavoriteStates = mutableListOf<Boolean>()
    private var playlistIndex = 0
    private var alternateUrl = ""
    private var usingAlternateSource = false
    private var openedAtMs = 0L
    private var lastProgressAtMs = 0L
    private var lastPositionMs = 0L
    private var hasStarted = false
    private var hasRenderedVideoFrame = false
    private var controlsVisible = false
    private var changingProgress = false
    private var keyboardMuted = false
    private var volumeBeforeMute = 1f
    private var externalSubtitleUri: Uri? = null
    private var externalSubtitleName = ""
    private var heldSeekKeyCode = KeyEvent.KEYCODE_UNKNOWN
    private var heldSeekAnchorMs = 0L
    private var pendingBufferMessage = ""
    private var selectedResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    private var returningToEmbeddedEngine = false
    private val isTelevisionDevice: Boolean
        get() = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK ==
            Configuration.UI_MODE_TYPE_TELEVISION

    private data class TrackChoice(
        val group: Tracks.Group,
        val trackIndex: Int,
        val label: String
    )

    private val hideControls = Runnable { hideControls() }
    private val hideSeekFeedback = Runnable {
        if (::seekFeedback.isInitialized) {
            seekFeedback.animate()
                .alpha(0f)
                .setDuration(140L)
                .withEndAction { seekFeedback.visibility = View.GONE }
                .start()
        }
    }
    private val revealBufferingBadge = Runnable {
        if (
            ::bufferingBadge.isInitialized &&
            !terminalError &&
            ::player.isInitialized &&
            player.playbackState == Player.STATE_BUFFERING
        ) {
            bufferingBadge.text = pendingBufferMessage
            bufferingBadge.alpha = 1f
            bufferingBadge.visibility = View.VISIBLE
        }
    }
    private val progressUpdater = object : Runnable {
        override fun run() {
            updateProgressUi()
            handler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    private val watchdog = object : Runnable {
        override fun run() {
            if (::player.isInitialized && !retryScheduled && !terminalError) {
                val now = SystemClock.elapsedRealtime()
                val position = player.currentPosition.coerceAtLeast(0L)
                if (player.isPlaying && position > lastPositionMs) {
                    markProgress(now, position)
                }
                if (
                    player.isPlaying &&
                    !hasRenderedVideoFrame &&
                    openedAtMs > 0L &&
                    now - openedAtMs >= FIRST_VIDEO_FRAME_TIMEOUT_MS
                ) {
                    // Never leave the viewer listening to audio over a black
                    // SurfaceView. Stop sound immediately and retry the native
                    // decoder; after bounded attempts the visible error panel
                    // remains available with a focused Retry action.
                    player.playWhenReady = false
                    scheduleRetry("Video frames were not rendered on this TV.")
                } else if (
                    !hasStarted &&
                    openedAtMs > 0L &&
                    now - openedAtMs >= STARTUP_TIMEOUT_MS
                ) {
                    scheduleRetry("The provider took too long to start this stream.")
                } else if (
                    isLive &&
                    hasStarted &&
                    player.playbackState == Player.STATE_BUFFERING &&
                    now - lastProgressAtMs >= LIVE_STALL_TIMEOUT_MS
                ) {
                    scheduleRetry("The live stream stopped sending data.")
                }
            }
            handler.postDelayed(this, WATCHDOG_INTERVAL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        url = intent.getStringExtra(EXTRA_URL).orEmpty()
        isLive = intent.getBooleanExtra(EXTRA_IS_LIVE, false)
        playbackMode = Media3PlaybackMode.from(
            intent.getStringExtra(EXTRA_PLAYBACK_MODE)
        )
        playlistUrls = intent.getStringArrayListExtra(EXTRA_PLAYLIST_URLS)
            ?.filter { it.isNotBlank() }
            .orEmpty()
        playlistAlternateUrls = intent
            .getStringArrayListExtra(EXTRA_PLAYLIST_ALTERNATE_URLS)
            .orEmpty()
        playlistTitles = intent.getStringArrayListExtra(EXTRA_PLAYLIST_TITLES)
            .orEmpty()
        playlistFavoriteKeys = intent
            .getStringArrayListExtra(EXTRA_PLAYLIST_FAVORITE_KEYS)
            .orEmpty()
        playlistFavoriteStates = intent
            .getBooleanArrayExtra(EXTRA_PLAYLIST_FAVORITE_STATES)
            ?.toMutableList()
            ?: mutableListOf()
        if (playlistUrls.isEmpty()) {
            playlistUrls = listOf(url)
            playlistAlternateUrls = listOf("")
            playlistTitles = listOf(intent.getStringExtra(EXTRA_TITLE).orEmpty())
        }
        if (playlistAlternateUrls.size != playlistUrls.size) {
            playlistAlternateUrls = List(playlistUrls.size) { "" }
        }
        if (playlistFavoriteKeys.size != playlistUrls.size) {
            playlistFavoriteKeys = List(playlistUrls.size) { "" }
        }
        if (playlistFavoriteStates.size != playlistUrls.size) {
            playlistFavoriteStates = MutableList(playlistUrls.size) { false }
        }
        playlistIndex = intent.getIntExtra(EXTRA_INITIAL_INDEX, 0)
            .coerceIn(0, playlistUrls.lastIndex)
        selectPreferredSource(playlistIndex)
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
            // Lumen renders a compact top status pill so buffering feedback
            // never sits behind the transport controls.
            setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            // The native SurfaceView remains in charge of video rendering, but
            // Lumen owns every visible control and every D-pad focus edge.
            setUseController(false)
            isFocusable = true
            keepScreenOn = true
            setKeepContentOnPlayerReset(true)
        }
        root.addView(playerView)
        titleBar = buildTitleBar().apply { visibility = View.GONE }
        root.addView(titleBar)
        controlsBar = buildControlsBar().apply { visibility = View.GONE }
        root.addView(controlsBar)
        centerTransport = buildCenterTransport().apply { visibility = View.GONE }
        root.addView(centerTransport)
        bufferingBadge = buildBufferingBadge()
        root.addView(bufferingBadge)
        seekFeedback = buildSeekFeedback()
        root.addView(seekFeedback)
        errorPanel = buildErrorPanel()
        root.addView(errorPanel)
        setContentView(root)

        player = buildPlayer()
        playerView.player = player
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                updateTransportUi()
                when (state) {
                    Player.STATE_BUFFERING -> showBufferingStatus(
                        if (isLive) "Building live buffer…" else "Buffering…"
                    )
                    Player.STATE_READY -> {
                        retryScheduled = false
                        errorPanel.visibility = View.GONE
                        hideBufferingStatus()
                    }
                    Player.STATE_ENDED -> {
                        if (isLive) {
                            scheduleRetry("The live feed ended. Reconnecting…")
                        } else if (playlistIndex < playlistUrls.lastIndex) {
                            openPlaylistItem(playlistIndex + 1)
                        }
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                scheduleRetry(friendlyError(error))
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                updateTransportUi()
                if (isPlaying) {
                    markProgress(
                        SystemClock.elapsedRealtime(),
                        player.currentPosition.coerceAtLeast(0L)
                    )
                    scheduleControlsHide()
                } else {
                    handler.removeCallbacks(hideControls)
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                updateTrackButtons(tracks)
            }

            override fun onRenderedFirstFrame() {
                hasRenderedVideoFrame = true
                // Do not let audio run ahead over a black surface. Sound is
                // released only when Android confirms that a video frame has
                // actually reached the television display.
                player.volume = if (keyboardMuted) 0f else volumeBeforeMute
                markHealthy(
                    SystemClock.elapsedRealtime(),
                    player.currentPosition.coerceAtLeast(0L)
                )
                // Start movies and channels in a clean cinema view. When a
                // reconnect or channel switch completes while the viewer is
                // already navigating the controller, keep that focus visible.
                if (!playerControlsHaveFocus()) hideControls(force = true)
            }
        })
        updateNavigationUi()
        updateFavoriteUi()
        updateTransportUi()
        open()
        handler.post(watchdog)
        handler.post(progressUpdater)
        playerView.requestFocus()
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

        // Keep a meaningful forward cushion while using short start/resume
        // gates. Loading continues in the background after playback begins.
        val buffers = Media3PlaybackPolicy.buffers(isLive, playbackMode)
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                buffers.minBufferMs,
                buffers.maxBufferMs,
                buffers.bufferForPlaybackMs,
                buffers.bufferForPlaybackAfterRebufferMs
            )
            .setBackBuffer(
                buffers.backBufferMs,
                buffers.retainBackBufferFromKeyframe
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        // DefaultDataSource delegates network requests to the hardened HTTP
        // factory and content:// subtitle files to Android's content resolver.
        val networkFactory = if (isLive) {
            LiveReconnectDataSource.Factory(
                upstreamFactory = http,
                reconnectDelayMs = Media3PlaybackPolicy.eofReconnectDelayMs(
                    playbackMode
                ),
                shouldReconnectAtEof = ::currentSourceIsRawTransportStream
            )
        } else {
            http
        }
        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(DefaultDataSource.Factory(this, networkFactory))
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(3))
        val renderers = DefaultRenderersFactory(this)
            // If a TV advertises a broken preferred decoder, allow Media3 to
            // fall through to another compatible decoder instead of yielding
            // audio with no picture.
            .setEnableDecoderFallback(true)
        return ExoPlayer.Builder(this, renderers)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
            .build()
    }

    private fun currentSourceIsRawTransportStream(): Boolean {
        val path = Uri.parse(url).path.orEmpty()
        return isLive && path.endsWith(".ts", ignoreCase = true)
    }

    private fun buildTitleBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(48), dp(22), dp(48), dp(38))
            background = topScrim()
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }
        backButton = themedButton("‹", "Back to Lumen", round = true) { finish() }.apply {
            textSize = 30f
            setPadding(0, 0, 0, dp(3))
        }
        val titleGroup = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(18), 0, dp(18), 0)
        }
        titleText = TextView(this).apply {
            textSize = 22f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(Color.WHITE)
            maxLines = 1
        }
        titleSubtitleText = TextView(this).apply {
            textSize = 13f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            setTextColor(0xFFBCC3B9.toInt())
            maxLines = 1
            setPadding(0, dp(2), 0, 0)
        }
        titleGroup.addView(titleText)
        titleGroup.addView(titleSubtitleText)
        val kind = TextView(this).apply {
            text = if (isLive) "●  LIVE" else "LUMEN"
            textSize = 12f
            letterSpacing = 0.14f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(0xFFC5FF63.toInt())
            gravity = Gravity.CENTER
            setPadding(dp(13), 0, dp(13), 0)
            background = roundedRect(0x73111511, 0x667F877D, 1, 18)
        }
        updateTitleUi()
        bar.addView(backButton, LinearLayout.LayoutParams(dp(46), dp(46)))
        bar.addView(titleGroup, LinearLayout.LayoutParams(0, dp(58), 1f))
        bar.addView(kind, LinearLayout.LayoutParams(dp(102), dp(34)))
        return bar
    }

    private fun updateTitleUi() {
        if (!::titleText.isInitialized || !::titleSubtitleText.isInitialized) return
        val rawTitle = playlistTitles.getOrNull(playlistIndex)
            ?.trim()
            .orEmpty()
            .ifBlank { if (isLive) "Live channel" else "Now playing" }
        val parts = rawTitle.split(" - ")
            .map { it.trim() }
            .filter { it.isNotBlank() }
        val headline = parts.firstOrNull().orEmpty().ifBlank { rawTitle }
        val details = parts.drop(1)
            .filterNot { it.equals(headline, ignoreCase = true) }
            .joinToString("  •  ")
        titleText.text = headline
        titleSubtitleText.text = details
        titleSubtitleText.visibility = if (details.isBlank()) View.GONE else View.VISIBLE
    }

    private fun buildCenterTransport(): LinearLayout {
        previousButton = iconButton(
            R.drawable.ic_player_previous,
            if (isLive) "Previous channel" else "Previous episode"
        ) { openPlaylistItem(playlistIndex - 1, navigationDirection = -1) }
        rewindButton = iconButton(
            R.drawable.ic_player_rewind,
            "Rewind 10 seconds"
        ) {
            seekBy(-SEEK_INCREMENT_MS)
            showSeekFeedback(-SEEK_INCREMENT_MS)
        }
        playPauseButton = iconButton(
            R.drawable.ic_player_pause,
            "Pause playback",
            prominent = true
        ) { togglePlayPause() }
        forwardButton = iconButton(
            R.drawable.ic_player_forward,
            "Fast forward 10 seconds"
        ) {
            seekBy(SEEK_INCREMENT_MS)
            showSeekFeedback(SEEK_INCREMENT_MS)
        }
        nextButton = iconButton(
            R.drawable.ic_player_next,
            if (isLive) "Next channel" else "Next episode"
        ) { openPlaylistItem(playlistIndex + 1, navigationDirection = 1) }

        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            background = roundedRect(0x99111511.toInt(), 0x66596157, 1, 40)
            setPadding(dp(8), dp(7), dp(8), dp(7))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
            addView(previousButton, transportParams(dp(52), dp(52)))
            addView(rewindButton, transportParams(dp(52), dp(52)))
            addView(playPauseButton, transportParams(dp(68), dp(68)))
            addView(forwardButton, transportParams(dp(52), dp(52)))
            addView(nextButton, transportParams(dp(52), dp(52)))
        }
    }

    private fun buildBufferingBadge(): TextView = TextView(this).apply {
        text = Media3PlaybackPolicy.bufferingLabel(isLive, reconnecting = false)
        textSize = 13f
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        setTextColor(0xFFE6EAE3.toInt())
        gravity = Gravity.CENTER
        setPadding(dp(16), dp(8), dp(16), dp(8))
        background = roundedRect(0xD9111511.toInt(), 0x4DC5FF63, 1, 18)
        visibility = View.GONE
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        ).apply { bottomMargin = dp(142) }
    }

    private fun buildSeekFeedback(): TextView = TextView(this).apply {
        textSize = 19f
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        setTextColor(0xFFC5FF63.toInt())
        gravity = Gravity.CENTER
        setPadding(dp(20), dp(12), dp(20), dp(12))
        background = roundedRect(0xE6111511.toInt(), 0x99C5FF63.toInt(), 1, 24)
        alpha = 0f
        visibility = View.GONE
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        )
    }

    private fun showBufferingStatus(message: String) {
        if (!::bufferingBadge.isInitialized || terminalError) return
        val reconnecting = retryAttempt > 0 || retryScheduled ||
            message.contains("reconnect", ignoreCase = true) ||
            message.contains("recover", ignoreCase = true) ||
            message.contains("compatible", ignoreCase = true)
        pendingBufferMessage = Media3PlaybackPolicy.bufferingLabel(isLive, reconnecting)
        handler.removeCallbacks(revealBufferingBadge)
        if (bufferingBadge.visibility == View.VISIBLE) {
            bufferingBadge.text = pendingBufferMessage
        } else {
            handler.postDelayed(revealBufferingBadge, BUFFERING_BADGE_DELAY_MS)
        }
    }

    private fun hideBufferingStatus() {
        handler.removeCallbacks(revealBufferingBadge)
        pendingBufferMessage = ""
        if (::bufferingBadge.isInitialized) bufferingBadge.visibility = View.GONE
    }

    private fun showSeekFeedback(offsetMs: Long) {
        if (!::seekFeedback.isInitialized || isLive) return
        handler.removeCallbacks(hideSeekFeedback)
        val seconds = kotlin.math.abs(offsetMs / 1_000L)
        val amount = if (seconds >= 60L && seconds % 60L == 0L) {
            "${seconds / 60L}m"
        } else {
            "${seconds}s"
        }
        seekFeedback.text = if (offsetMs < 0L) "−$amount" else "+$amount"
        val side = Media3PlaybackPolicy.seekFeedbackSide(
            offsetMs,
            isTelevision = isTelevisionDevice
        )
        seekFeedback.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            when (side) {
                SeekFeedbackSide.LEFT -> Gravity.CENTER_VERTICAL or Gravity.LEFT
                SeekFeedbackSide.RIGHT -> Gravity.CENTER_VERTICAL or Gravity.RIGHT
                SeekFeedbackSide.CENTER -> Gravity.CENTER
            }
        ).apply {
            if (side == SeekFeedbackSide.LEFT) marginStart = dp(96)
            if (side == SeekFeedbackSide.RIGHT) marginEnd = dp(96)
        }
        seekFeedback.animate().cancel()
        seekFeedback.alpha = 0f
        seekFeedback.visibility = View.VISIBLE
        seekFeedback.animate().alpha(1f).setDuration(100L).start()
        handler.postDelayed(hideSeekFeedback, 650L)
    }

    private fun buildControlsBar(): View {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(52), dp(54), dp(52), dp(22))
            background = bottomScrim()
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        }

        val progressRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        positionText = playerTimeText().apply {
            text = if (isLive) "● LIVE" else "0:00"
            if (isLive) setTextColor(0xFFC5FF63.toInt())
        }
        progressBar = SeekBar(this).apply {
            id = View.generateViewId()
            max = 1_000
            progress = 0
            keyProgressIncrement = SEEK_INCREMENT_MS.toInt()
            isFocusable = !isLive
            visibility = if (isLive) View.GONE else View.VISIBLE
            splitTrack = false
            progressDrawable = seekProgressDrawable()
            thumb = seekThumb(focused = false)
            thumbOffset = 0
            contentDescription = "Playback position"
            setOnFocusChangeListener { _, focused ->
                if (focused) {
                    logFocus("Playback position")
                    handler.removeCallbacks(hideControls)
                } else {
                    scheduleControlsHide()
                }
                // Keep the track dimensions fixed. Focus is communicated by
                // the thumb and glow so the bar never appears to shrink.
                thumb = seekThumb(focused)
            }
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(
                    seekBar: SeekBar,
                    progress: Int,
                    fromUser: Boolean
                ) {
                    if (fromUser && !changingProgress && ::player.isInitialized) {
                        player.seekTo(progress.toLong())
                        positionText.text = formatTime(progress.toLong())
                        showControls()
                    }
                }

                override fun onStartTrackingTouch(seekBar: SeekBar) {
                    handler.removeCallbacks(hideControls)
                }

                override fun onStopTrackingTouch(seekBar: SeekBar) {
                    scheduleControlsHide()
                }
            })
        }
        durationText = playerTimeText().apply {
            text = if (isLive) "" else "0:00"
            visibility = if (isLive) View.GONE else View.VISIBLE
        }
        bufferedText = playerTimeText().apply {
            text = if (isLive) "Preparing signal" else "0s ready"
            visibility = View.GONE
        }
        progressRow.addView(positionText, LinearLayout.LayoutParams(dp(76), dp(40)))
        progressRow.addView(
            progressBar,
            LinearLayout.LayoutParams(0, dp(40), 1f).apply {
                marginStart = dp(10)
                marginEnd = dp(10)
            }
        )
        progressRow.addView(durationText, LinearLayout.LayoutParams(dp(76), dp(40)))

        playlistButton = toolButton(
            "▦",
            if (isLive) "Channels" else "Episodes",
            if (isLive) "Choose a channel" else "Choose an episode"
        ) {
            showPlaylistDialog()
        }
        subtitleButton = toolButton("CC", "Subtitles", "Choose or add subtitles") {
            showSubtitleDialog()
        }.apply { isEnabled = !isLive }
        audioButton = toolButton("♪", "Audio", "Choose audio track") {
            showTrackDialog(C.TRACK_TYPE_AUDIO, "Audio", allowOff = false)
        }.apply { isEnabled = false }
        qualityButton = toolButton("HD", "Quality", "Choose video quality") {
            showTrackDialog(C.TRACK_TYPE_VIDEO, "Quality", allowOff = false)
        }.apply { isEnabled = false }
        moreButton = toolButton("⋮", "More", "More playback options") {
            showMoreDialog()
        }

        val tools = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        tools.addView(playlistButton, transportParams(dp(104), dp(62)))
        tools.addView(subtitleButton, transportParams(dp(104), dp(62)))
        tools.addView(audioButton, transportParams(dp(104), dp(62)))
        tools.addView(qualityButton, transportParams(dp(104), dp(62)))
        tools.addView(moreButton, transportParams(dp(104), dp(62)))
        panel.addView(
            progressRow,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        panel.addView(
            tools,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(66)
            )
        )
        return panel
    }

    private fun toolButton(
        glyph: String,
        label: String,
        description: String,
        onClick: () -> Unit
    ): TextView = themedButton(
        "$glyph\n$label",
        description,
        onClick = onClick
    ).apply {
        textSize = 11f
        setLineSpacing(dp(2).toFloat(), 1f)
        setPadding(dp(10), dp(6), dp(10), dp(5))
        background = toolButtonBackground()
        setTextColor(toolButtonTextColors())
    }

    private fun playerTimeText(): TextView = TextView(this).apply {
        textSize = 15f
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        setTextColor(0xFFD8DDD5.toInt())
        gravity = Gravity.CENTER
        maxLines = 1
    }

    private fun transportParams(width: Int, height: Int): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(width, height).apply {
            marginStart = dp(5)
            marginEnd = dp(5)
        }

    private fun themedButton(
        label: String,
        description: String,
        showPlayerControlsOnFocus: Boolean = true,
        prominent: Boolean = false,
        round: Boolean = false,
        onClick: () -> Unit
    ): TextView = TextView(this).apply {
        id = View.generateViewId()
        text = label
        contentDescription = description
        textSize = if (prominent) 22f else 14f
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        gravity = Gravity.CENTER
        includeFontPadding = false
        isFocusable = true
        isClickable = true
        setPadding(dp(12), 0, dp(12), 0)
        background = buttonBackground(prominent, round)
        setTextColor(
            ColorStateList(
                arrayOf(
                    intArrayOf(-android.R.attr.state_enabled),
                    intArrayOf(android.R.attr.state_focused),
                    intArrayOf(android.R.attr.state_pressed),
                    intArrayOf()
                ),
                intArrayOf(
                    0x667F877D,
                    0xFF0B0D0B.toInt(),
                    0xFF0B0D0B.toInt(),
                    if (prominent) 0xFFC5FF63.toInt() else Color.WHITE
                )
            )
        )
        setOnFocusChangeListener { view, focused ->
            if (focused) {
                logFocus(view.contentDescription?.toString() ?: label)
                handler.removeCallbacks(hideControls)
                if (showPlayerControlsOnFocus) showControls()
            } else if (showPlayerControlsOnFocus) {
                scheduleControlsHide()
            }
            view.animate()
                .scaleX(if (focused) 1.08f else 1f)
                .scaleY(if (focused) 1.08f else 1f)
                .setDuration(120L)
                .start()
            view.elevation = if (focused) dp(10).toFloat() else 0f
        }
        setOnClickListener {
            onClick()
            showControls()
        }
    }

    private fun iconButton(
        icon: Int,
        description: String,
        prominent: Boolean = false,
        onClick: () -> Unit
    ): ImageButton = ImageButton(this).apply {
        id = View.generateViewId()
        contentDescription = description
        setImageResource(icon)
        scaleType = ImageView.ScaleType.CENTER_INSIDE
        val inset = dp(if (prominent) 19 else 15)
        setPadding(inset, inset, inset, inset)
        background = if (prominent) {
            centerButtonBackground()
        } else {
            buttonBackground(round = true)
        }
        imageTintList = ColorStateList(
            arrayOf(
                intArrayOf(-android.R.attr.state_enabled),
                intArrayOf(android.R.attr.state_focused),
                intArrayOf(android.R.attr.state_pressed),
                intArrayOf()
            ),
            intArrayOf(
                0x667F877D,
                0xFF0B0D0B.toInt(),
                0xFF0B0D0B.toInt(),
                if (prominent) 0xFFC5FF63.toInt() else Color.WHITE
            )
        )
        isFocusable = true
        isClickable = true
        setOnFocusChangeListener { view, focused ->
            if (focused) {
                logFocus(view.contentDescription?.toString() ?: description)
                handler.removeCallbacks(hideControls)
                showControls()
            } else {
                scheduleControlsHide()
            }
            view.animate()
                .scaleX(if (focused) 1.08f else 1f)
                .scaleY(if (focused) 1.08f else 1f)
                .setDuration(120L)
                .start()
            view.elevation = if (focused) dp(10).toFloat() else 0f
        }
        setOnClickListener {
            onClick()
            showControls()
        }
    }

    private fun toolButtonTextColors(): ColorStateList = ColorStateList(
        arrayOf(
            intArrayOf(-android.R.attr.state_enabled),
            intArrayOf(android.R.attr.state_focused),
            intArrayOf(android.R.attr.state_pressed),
            intArrayOf()
        ),
        intArrayOf(
            0x667F877D,
            0xFFC5FF63.toInt(),
            0xFFC5FF63.toInt(),
            Color.WHITE
        )
    )

    private fun toolButtonBackground(): StateListDrawable = StateListDrawable().apply {
        addState(
            intArrayOf(-android.R.attr.state_enabled),
            roundedRect(0x26111511, 0x26596157, 1, 12)
        )
        addState(
            intArrayOf(android.R.attr.state_focused),
            roundedRect(0xC2111511.toInt(), 0xFFC5FF63.toInt(), 2, 12)
        )
        addState(
            intArrayOf(android.R.attr.state_pressed),
            roundedRect(0xE6111511.toInt(), 0xFFE0FFAA.toInt(), 2, 12)
        )
        addState(
            intArrayOf(),
            roundedRect(0x4D111511, 0x40596157, 1, 12)
        )
    }

    private fun centerButtonBackground(): StateListDrawable = StateListDrawable().apply {
        addState(
            intArrayOf(android.R.attr.state_focused),
            roundedRect(0xFFC5FF63.toInt(), Color.WHITE, 2, 40)
        )
        addState(
            intArrayOf(android.R.attr.state_pressed),
            roundedRect(0xE6111511.toInt(), 0xFFE0FFAA.toInt(), 2, 40)
        )
        addState(
            intArrayOf(),
            roundedRect(0x99111511.toInt(), 0xB3C5FF63.toInt(), 1, 40)
        )
    }

    private fun seekProgressDrawable(): LayerDrawable {
        val backgroundTrack = roundedRect(0x667F877D, Color.TRANSPARENT, 0, 2)
        val bufferedTrack = ClipDrawable(
            roundedRect(0xB3AEB5AA.toInt(), Color.TRANSPARENT, 0, 2),
            Gravity.START,
            ClipDrawable.HORIZONTAL
        )
        val playedTrack = ClipDrawable(
            roundedRect(0xFFC5FF63.toInt(), Color.TRANSPARENT, 0, 2),
            Gravity.START,
            ClipDrawable.HORIZONTAL
        )
        return LayerDrawable(arrayOf(backgroundTrack, bufferedTrack, playedTrack)).apply {
            setId(0, android.R.id.background)
            setId(1, android.R.id.secondaryProgress)
            setId(2, android.R.id.progress)
            for (index in 0..2) {
                setLayerHeight(index, dp(4))
                setLayerGravity(index, Gravity.CENTER_VERTICAL)
            }
        }
    }

    private fun seekThumb(focused: Boolean): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(0xFFC5FF63.toInt())
        setStroke(
            dp(if (focused) 2 else 1),
            if (focused) Color.WHITE else 0xCC0B0D0B.toInt()
        )
        val size = dp(if (focused) 14 else 11)
        setSize(size, size)
    }

    private fun buttonBackground(
        prominent: Boolean = false,
        round: Boolean = false
    ): StateListDrawable = StateListDrawable().apply {
        val radius = if (round) 40 else 14
        addState(
            intArrayOf(-android.R.attr.state_enabled),
            roundedRect(0x55262B24, 0x334F554D, 1, radius)
        )
        addState(
            intArrayOf(android.R.attr.state_focused),
            roundedRect(
                if (prominent) 0xFFE0FFAA.toInt() else 0xFFC5FF63.toInt(),
                Color.WHITE,
                2,
                radius
            )
        )
        addState(
            intArrayOf(android.R.attr.state_pressed),
            roundedRect(0xFFE0FFAA.toInt(), Color.WHITE, 2, radius)
        )
        addState(
            intArrayOf(),
            roundedRect(
                0xD9111511.toInt(),
                if (prominent) 0x99C5FF63.toInt() else 0x99596157.toInt(),
                1,
                radius
            )
        )
    }

    private fun roundedRect(
        fill: Int,
        stroke: Int,
        strokeWidth: Int,
        radius: Int = 14
    ): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radius).toFloat()
            setColor(fill)
            setStroke(dp(strokeWidth), stroke)
        }

    private fun topScrim(): GradientDrawable = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        intArrayOf(0xC7000000.toInt(), 0x66000000, Color.TRANSPARENT)
    )

    private fun bottomScrim(): GradientDrawable = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        intArrayOf(Color.TRANSPARENT, 0xA6000000.toInt(), 0xEB000000.toInt())
    )

    private fun updateNavigationUi() {
        if (!::previousButton.isInitialized) return
        previousButton.isEnabled = playlistIndex > 0
        nextButton.isEnabled = playlistIndex < playlistUrls.lastIndex
        val showPlaylistNavigation = Media3PlaybackPolicy.showPlaylistNavigation(
            isTelevisionDevice,
            playlistUrls.size
        )
        previousButton.visibility = if (showPlaylistNavigation) View.VISIBLE else View.GONE
        nextButton.visibility = if (showPlaylistNavigation) View.VISIBLE else View.GONE
        val showSeekNavigation = Media3PlaybackPolicy.showSeekNavigation(
            isTelevisionDevice,
            isLive
        )
        rewindButton.visibility = if (showSeekNavigation) View.VISIBLE else View.GONE
        forwardButton.visibility = if (showSeekNavigation) View.VISIBLE else View.GONE
        playlistButton.isEnabled = playlistUrls.size > 1
        playlistButton.visibility = if (playlistUrls.size > 1) View.VISIBLE else View.GONE
        playlistButton.text = if (isLive) "▦\nChannels" else "▦\nEpisodes"
        updateTitleUi()
        updateFocusGraph()
        updateErrorNavigationUi()
    }

    private fun updateFocusGraph() {
        if (!::backButton.isInitialized || !::playPauseButton.isInitialized) return
        val tools = listOf(
            playlistButton,
            subtitleButton,
            audioButton,
            qualityButton,
            moreButton
        ).filter {
            it.visibility == View.VISIBLE && it.isEnabled
        }
        tools.forEachIndexed { index, button ->
            button.nextFocusLeftId = tools.getOrNull(index - 1)?.id ?: button.id
            button.nextFocusRightId = tools.getOrNull(index + 1)?.id ?: button.id
            button.nextFocusUpId = if (progressBar.visibility == View.VISIBLE) {
                progressBar.id
            } else {
                playPauseButton.id
            }
            button.nextFocusDownId = button.id
        }
        val transportControls = listOf(
            previousButton,
            rewindButton,
            playPauseButton,
            forwardButton,
            nextButton
        ).filter {
            it.visibility == View.VISIBLE && it.isEnabled
        }
        val transportDownId = if (progressBar.visibility == View.VISIBLE) {
            progressBar.id
        } else {
            tools.firstOrNull()?.id ?: playPauseButton.id
        }
        transportControls.forEachIndexed { index, button ->
            button.nextFocusLeftId = transportControls.getOrNull(index - 1)?.id
                ?: button.id
            button.nextFocusRightId = transportControls.getOrNull(index + 1)?.id
                ?: button.id
            button.nextFocusUpId = backButton.id
            button.nextFocusDownId = transportDownId
        }
        backButton.nextFocusLeftId = backButton.id
        backButton.nextFocusRightId = backButton.id
        backButton.nextFocusUpId = backButton.id
        backButton.nextFocusDownId = playPauseButton.id
        if (progressBar.visibility == View.VISIBLE) {
            progressBar.nextFocusUpId = playPauseButton.id
            progressBar.nextFocusDownId = tools.firstOrNull()?.id ?: progressBar.id
        }
        playerView.nextFocusUpId = backButton.id
        playerView.nextFocusDownId = playPauseButton.id
    }

    private fun openPlaylistItem(index: Int, navigationDirection: Int = 0) {
        if (index !in playlistUrls.indices || index == playlistIndex) return
        retryAttempt = 0
        retryScheduled = false
        terminalError = false
        playlistIndex = index
        selectPreferredSource(index)
        externalSubtitleUri = null
        externalSubtitleName = ""
        updateNavigationUi()
        updateFavoriteUi()
        open()
        showControls()
        if (!isLive && navigationDirection != 0) {
            playPauseButton.requestFocus()
        } else if (navigationDirection < 0 && previousButton.isEnabled) {
            previousButton.requestFocus()
        } else if (navigationDirection > 0 && nextButton.isEnabled) {
            nextButton.requestFocus()
        } else if (navigationDirection != 0) {
            playPauseButton.requestFocus()
        } else if (playlistButton.visibility == View.VISIBLE && playlistButton.isEnabled) {
            playlistButton.requestFocus()
        } else {
            playPauseButton.requestFocus()
        }
    }

    private fun togglePlayPause() {
        if (player.isPlaying) {
            player.pause()
        } else {
            if (player.playbackState == Player.STATE_ENDED) player.seekTo(0L)
            player.play()
        }
        updateTransportUi()
    }

    private fun toggleKeyboardMute() {
        if (keyboardMuted) {
            keyboardMuted = false
            player.volume = volumeBeforeMute.coerceAtLeast(0.1f)
        } else {
            if (player.volume > 0f) volumeBeforeMute = player.volume
            keyboardMuted = true
            player.volume = 0f
        }
        Toast.makeText(
            this,
            if (keyboardMuted) "Muted" else "Sound on",
            Toast.LENGTH_SHORT
        ).show()
    }

    private fun seekBy(offsetMs: Long) {
        if (isLive || !::player.isInitialized) return
        val duration = player.duration.takeIf { it > 0L }
        val target = (player.currentPosition + offsetMs).coerceAtLeast(0L)
        player.seekTo(duration?.let { target.coerceAtMost(it) } ?: target)
        updateProgressUi()
    }

    private fun seekFromHeldKey(event: KeyEvent, direction: Int) {
        if (isLive || !::player.isInitialized) return
        if (event.repeatCount == 0 || heldSeekKeyCode != event.keyCode) {
            heldSeekKeyCode = event.keyCode
            heldSeekAnchorMs = player.currentPosition
        }
        val distance = Media3PlaybackPolicy.heldSeekDistanceMs(event.repeatCount)
        val offset = distance * direction
        val duration = player.duration.takeIf { it > 0L }
        val target = (heldSeekAnchorMs + offset).coerceAtLeast(0L)
        player.seekTo(duration?.let { target.coerceAtMost(it) } ?: target)
        updateProgressUi()
        showSeekFeedback(offset)
    }

    private fun updateTransportUi() {
        if (!::playPauseButton.isInitialized || !::player.isInitialized) return
        val playing = player.isPlaying
        playPauseButton.setImageResource(
            if (playing) R.drawable.ic_player_pause
            else R.drawable.ic_player_play
        )
        playPauseButton.contentDescription = if (playing) {
            "Pause playback"
        } else {
            "Play"
        }
    }

    private fun updateTrackButtons(tracks: Tracks = player.currentTracks) {
        if (
            !::subtitleButton.isInitialized ||
            !::audioButton.isInitialized ||
            !::qualityButton.isInitialized
        ) return
        val subtitleCount = trackChoices(tracks, C.TRACK_TYPE_TEXT).size
        val audioCount = trackChoices(tracks, C.TRACK_TYPE_AUDIO).size
        val videoCount = trackChoices(tracks, C.TRACK_TYPE_VIDEO).size
        // Movies can always import a local subtitle, even when the stream has
        // no embedded text tracks. Live keeps the button only for embedded CC.
        subtitleButton.isEnabled = !isLive || subtitleCount > 0
        audioButton.isEnabled = audioCount > 1
        qualityButton.isEnabled = videoCount > 1
        subtitleButton.text = if (externalSubtitleUri != null) {
            "CC\nAdded"
        } else if (
            player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
        ) {
            "CC\nOff"
        } else {
            "CC\nSubtitles"
        }
        audioButton.text = "♪\nAudio"
        qualityButton.text = "HD\nQuality"
        updateFocusGraph()
    }

    private fun trackChoices(tracks: Tracks, type: Int): List<TrackChoice> {
        val choices = mutableListOf<TrackChoice>()
        tracks.groups.filter { it.type == type }.forEach { group ->
            for (index in 0 until group.length) {
                if (!group.isTrackSupported(index)) continue
                val format = group.getTrackFormat(index)
                val details = mutableListOf<String>()
                format.label?.takeIf { it.isNotBlank() }?.let(details::add)
                format.language?.takeIf {
                    it.isNotBlank() && !it.equals("und", ignoreCase = true)
                }?.let { language ->
                    if (details.none { it.equals(language, ignoreCase = true) }) {
                        details += language.uppercase()
                    }
                }
                if (type == C.TRACK_TYPE_AUDIO && format.channelCount > 0) {
                    details += when (format.channelCount) {
                        1 -> "Mono"
                        2 -> "Stereo"
                        6 -> "5.1"
                        8 -> "7.1"
                        else -> "${format.channelCount} channels"
                    }
                }
                if (type == C.TRACK_TYPE_VIDEO) {
                    if (format.height > 0) details += "${format.height}p"
                    if (format.bitrate > 0) {
                        details += String.format("%.1f Mbps", format.bitrate / 1_000_000f)
                    }
                }
                choices += TrackChoice(
                    group = group,
                    trackIndex = index,
                    label = details.joinToString(" · ").ifBlank {
                        when (type) {
                            C.TRACK_TYPE_AUDIO -> "Audio ${choices.size + 1}"
                            C.TRACK_TYPE_VIDEO -> "Quality ${choices.size + 1}"
                            else -> "Subtitle ${choices.size + 1}"
                        }
                    }
                )
            }
        }
        return choices
    }

    private fun showPlaylistDialog() {
        if (playlistUrls.size <= 1) return
        handler.removeCallbacks(hideControls)
        val fallbackName = if (isLive) "Channel" else "Episode"
        val labels = playlistUrls.indices.map { index ->
            playlistTitles.getOrNull(index)
                ?.trim()
                ?.takeIf { it.isNotBlank() }
                ?: "$fallbackName ${index + 1}"
        }.toTypedArray()
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (isLive) "Channels" else "Episodes")
            .setSingleChoiceItems(labels, playlistIndex) { activeDialog, index ->
                activeDialog.dismiss()
                if (index != playlistIndex) openPlaylistItem(index)
            }
            .setNegativeButton("Cancel", null)
            .create()
        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawable(
                roundedRect(0xFF111511.toInt(), 0xFF596157.toInt(), 1, 18)
            )
        }
        dialog.setOnDismissListener {
            showControls()
            playlistButton.post { playlistButton.requestFocus() }
        }
        dialog.show()
    }

    private fun showMoreDialog() {
        handler.removeCallbacks(hideControls)
        val modes = intArrayOf(
            AspectRatioFrameLayout.RESIZE_MODE_FIT,
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        )
        val selected = modes.indexOf(selectedResizeMode).coerceAtLeast(0)
        val favoriteKey = playlistFavoriteKeys.getOrNull(playlistIndex).orEmpty()
        val saved = playlistFavoriteStates.getOrNull(playlistIndex) == true
        val labels = buildList {
            add(if (selected == 0) "✓  Fit to screen" else "Fit to screen")
            add(if (selected == 1) "✓  Fill screen" else "Fill screen")
            if (favoriteKey.isNotBlank()) {
                add(if (saved) "♥  Remove from My List" else "♡  Add to My List")
            }
        }.toTypedArray()
        val dialog = AlertDialog.Builder(this)
            .setTitle("More")
            .setItems(labels) { activeDialog, index ->
                if (index < modes.size) {
                    selectedResizeMode = modes[index]
                    playerView.resizeMode = selectedResizeMode
                } else {
                    playlistFavoriteStates[playlistIndex] = !saved
                    updateFavoriteUi()
                    Toast.makeText(
                        this,
                        if (saved) "Removed from My List" else "Added to My List",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                activeDialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .create()
        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawable(
                roundedRect(0xFF111511.toInt(), 0xFF596157.toInt(), 1, 18)
            )
        }
        dialog.setOnDismissListener {
            showControls()
            moreButton.post { moreButton.requestFocus() }
        }
        dialog.show()
    }

    private fun updateFavoriteUi() {
        if (!::moreButton.isInitialized) return
        val available = playlistFavoriteKeys.getOrNull(playlistIndex).orEmpty().isNotBlank()
        val saved = playlistFavoriteStates.getOrNull(playlistIndex) == true
        moreButton.text = if (available && saved) "♥\nMore" else "⋮\nMore"
        moreButton.contentDescription = if (available && saved) {
            "More playback options, saved in My List"
        } else {
            "More playback options"
        }
    }

    private fun showSubtitleDialog() {
        val choices = trackChoices(player.currentTracks, C.TRACK_TYPE_TEXT)
        val canAddFile = !isLive
        if (choices.isEmpty() && !canAddFile) return
        handler.removeCallbacks(hideControls)
        val labels = buildList {
            add("Off")
            addAll(choices.map { it.label })
            if (canAddFile) add("＋  Add subtitle file…")
        }.toTypedArray()
        val typeDisabled = player.trackSelectionParameters.disabledTrackTypes
            .contains(C.TRACK_TYPE_TEXT)
        val selectedChoice = choices.indexOfFirst {
            it.group.isTrackSelected(it.trackIndex)
        }
        val selected = if (typeDisabled || selectedChoice < 0) {
            0
        } else {
            selectedChoice + 1
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle("Subtitles")
            .setSingleChoiceItems(labels, selected) { activeDialog, itemIndex ->
                when {
                    canAddFile && itemIndex == labels.lastIndex -> {
                        activeDialog.dismiss()
                        openSubtitlePicker()
                    }
                    itemIndex == 0 -> {
                        externalSubtitleUri = null
                        externalSubtitleName = ""
                        player.trackSelectionParameters =
                            player.trackSelectionParameters
                                .buildUpon()
                                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                                .build()
                        playerView.subtitleView?.setCues(emptyList())
                        activeDialog.dismiss()
                    }
                    else -> {
                        val choice = choices[itemIndex - 1]
                        player.trackSelectionParameters =
                            player.trackSelectionParameters
                                .buildUpon()
                                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                .addOverride(
                                    TrackSelectionOverride(
                                        choice.group.mediaTrackGroup,
                                        choice.trackIndex
                                    )
                                )
                                .build()
                        activeDialog.dismiss()
                    }
                }
            }
            .setNegativeButton("Cancel", null)
            .create()
        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawable(
                roundedRect(0xFF111511.toInt(), 0xFF596157.toInt(), 1)
            )
        }
        dialog.setOnDismissListener {
            updateTrackButtons()
            showControls()
            subtitleButton.post { subtitleButton.requestFocus() }
        }
        dialog.show()
    }

    private fun openSubtitlePicker() {
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
        try {
            startActivityForResult(picker, SUBTITLE_REQUEST_CODE)
        } catch (_: Exception) {
            Toast.makeText(
                this,
                "No file browser is available on this TV.",
                Toast.LENGTH_LONG
            ).show()
            showControls()
            subtitleButton.requestFocus()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SUBTITLE_REQUEST_CODE) return
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            showControls()
            subtitleButton.requestFocus()
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
            // The activity grant still remains valid for this playback.
        }
        externalSubtitleUri = uri
        externalSubtitleName = subtitleDisplayName(uri)
        val position = player.currentPosition.coerceAtLeast(0L)
        val shouldPlay = player.playWhenReady
        player.setMediaItem(buildMediaItem(), position)
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .build()
        player.prepare()
        player.playWhenReady = shouldPlay
        Toast.makeText(
            this,
            "Added $externalSubtitleName",
            Toast.LENGTH_SHORT
        ).show()
        showControls()
        subtitleButton.requestFocus()
    }

    private fun subtitleDisplayName(uri: Uri): String {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(0)?.takeIf { it.isNotBlank() }?.let { return it }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "External subtitle"
    }

    private fun subtitleMimeType(uri: Uri): String {
        val reported = contentResolver.getType(uri).orEmpty()
        if (reported.isNotBlank() && reported != "text/plain") return reported
        return when (subtitleDisplayName(uri).substringAfterLast('.', "").lowercase()) {
            "vtt" -> "text/vtt"
            "ssa" -> "text/x-ssa"
            "ass" -> "text/x-ass"
            "ttml", "xml" -> "application/ttml+xml"
            else -> "application/x-subrip"
        }
    }

    private fun buildMediaItem(): MediaItem {
        val builder = MediaItem.Builder().setUri(Uri.parse(url))
        if (Uri.parse(url).path.orEmpty().endsWith(".m3u8", ignoreCase = true)) {
            // Some IPTV endpoints omit a useful Content-Type. Declaring HLS
            // prevents a bad server header from selecting the wrong parser.
            builder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }
        externalSubtitleUri?.let { subtitleUri ->
            builder.setSubtitleConfigurations(
                listOf(
                    MediaItem.SubtitleConfiguration.Builder(subtitleUri)
                        .setMimeType(subtitleMimeType(subtitleUri))
                        .setLabel(externalSubtitleName)
                        .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                        .build()
                )
            )
        }
        return builder.build()
    }

    private fun showTrackDialog(type: Int, title: String, allowOff: Boolean) {
        val choices = trackChoices(player.currentTracks, type)
        if (choices.isEmpty()) return
        handler.removeCallbacks(hideControls)
        val offset = if (allowOff) 1 else 0
        val labels = buildList {
            if (allowOff) add("Off")
            addAll(choices.map { it.label })
        }.toTypedArray()
        val typeDisabled = player.trackSelectionParameters.disabledTrackTypes.contains(type)
        val selectedChoice = choices.indexOfFirst {
            it.group.isTrackSelected(it.trackIndex)
        }
        val selected = if (allowOff && (typeDisabled || selectedChoice < 0)) {
            0
        } else {
            (selectedChoice.coerceAtLeast(0) + offset)
        }
        val returnFocus = when (type) {
            C.TRACK_TYPE_TEXT -> subtitleButton
            C.TRACK_TYPE_VIDEO -> qualityButton
            else -> audioButton
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setSingleChoiceItems(labels, selected) { activeDialog, itemIndex ->
                val builder = player.trackSelectionParameters.buildUpon()
                    .clearOverridesOfType(type)
                if (allowOff && itemIndex == 0) {
                    builder.setTrackTypeDisabled(type, true)
                } else {
                    val choice = choices[itemIndex - offset]
                    builder
                        .setTrackTypeDisabled(type, false)
                        .addOverride(
                            TrackSelectionOverride(
                                choice.group.mediaTrackGroup,
                                choice.trackIndex
                            )
                        )
                }
                player.trackSelectionParameters = builder.build()
                activeDialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .create()
        dialog.setOnShowListener {
            dialog.window?.setBackgroundDrawable(
                roundedRect(0xFF111511.toInt(), 0xFF596157.toInt(), 1)
            )
        }
        dialog.setOnDismissListener {
            updateTrackButtons()
            showControls()
            returnFocus.post { returnFocus.requestFocus() }
        }
        dialog.show()
    }

    private fun updateProgressUi() {
        if (
            !::player.isInitialized ||
            !::progressBar.isInitialized ||
            changingProgress
        ) return
        val duration = player.duration
        val position = player.currentPosition.coerceAtLeast(0L)
        val bufferedPosition = player.bufferedPosition.coerceAtLeast(position)
        val bufferedAheadSeconds = ((bufferedPosition - position) / 1_000L)
            .coerceAtLeast(0L)
        bufferedText.text = if (bufferedAheadSeconds > 0L) {
            "${bufferedAheadSeconds}s ready"
        } else if (player.playbackState == Player.STATE_BUFFERING) {
            "Loading signal"
        } else {
            if (isLive) "Live edge" else "Playing"
        }
        if (isLive) return
        changingProgress = true
        if (duration > 0L) {
            val boundedDuration = duration.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            progressBar.max = boundedDuration
            progressBar.progress = position.coerceAtMost(duration)
                .coerceAtMost(Int.MAX_VALUE.toLong())
                .toInt()
            progressBar.secondaryProgress = bufferedPosition.coerceAtMost(duration)
                .coerceAtMost(Int.MAX_VALUE.toLong())
                .toInt()
            durationText.text = formatTime(duration)
        } else {
            progressBar.max = 1_000
            progressBar.progress = 0
            durationText.text = "--:--"
        }
        positionText.text = formatTime(position)
        changingProgress = false
    }

    private fun formatTime(milliseconds: Long): String {
        val totalSeconds = (milliseconds.coerceAtLeast(0L) / 1_000L)
        val seconds = totalSeconds % 60L
        val minutes = (totalSeconds / 60L) % 60L
        val hours = totalSeconds / 3_600L
        return if (hours > 0L) {
            "%d:%02d:%02d".format(hours, minutes, seconds)
        } else {
            "%d:%02d".format(minutes, seconds)
        }
    }

    private fun showControls(requestTransportFocus: Boolean = false) {
        if (
            terminalError ||
            !::controlsBar.isInitialized ||
            !::centerTransport.isInitialized
        ) return
        controlsVisible = true
        titleBar.animate().cancel()
        controlsBar.animate().cancel()
        centerTransport.animate().cancel()
        // Show immediately. Entry fades can visibly lag on budget 4K TVs
        // because a large video surface is being composed at the same time.
        titleBar.alpha = 1f
        controlsBar.alpha = 1f
        centerTransport.alpha = 1f
        titleBar.visibility = View.VISIBLE
        controlsBar.visibility = View.VISIBLE
        centerTransport.visibility = View.VISIBLE
        updateTransportUi()
        updateProgressUi()
        scheduleControlsHide()
        if (requestTransportFocus) {
            playPauseButton.post { playPauseButton.requestFocus() }
        }
    }

    private fun showControlsFromRemote() {
        showControls(
            requestTransportFocus = Media3PlaybackPolicy.focusTransportOnRemoteInput(
                isLive = isLive,
                controlsVisible = controlsVisible,
                playerSurfaceFocused = playerView.hasFocus()
            )
        )
    }

    private fun scheduleControlsHide() {
        handler.removeCallbacks(hideControls)
        if (
            ::player.isInitialized &&
            player.isPlaying &&
            !terminalError
        ) {
            handler.postDelayed(hideControls, CONTROLS_TIMEOUT_MS)
        }
    }

    private fun hideControls(force: Boolean = false) {
        if (!::controlsBar.isInitialized || terminalError) return
        if (!force && (!::player.isInitialized || !player.isPlaying)) return
        handler.removeCallbacks(hideControls)
        controlsVisible = false
        playerView.requestFocus()
        titleBar.animate().cancel()
        controlsBar.animate().cancel()
        centerTransport.animate().cancel()
        titleBar.animate()
            .alpha(0f)
            .setDuration(170L)
            .withEndAction {
                if (!controlsVisible) titleBar.visibility = View.GONE
            }
            .start()
        controlsBar.animate()
            .alpha(0f)
            .setDuration(170L)
            .withEndAction {
                if (!controlsVisible) controlsBar.visibility = View.GONE
            }
            .start()
        centerTransport.animate()
            .alpha(0f)
            .setDuration(150L)
            .withEndAction {
                if (!controlsVisible) centerTransport.visibility = View.GONE
            }
            .start()
    }

    private fun playerControlsHaveFocus(): Boolean =
        (::titleBar.isInitialized && titleBar.hasFocus()) ||
            (::controlsBar.isInitialized && controlsBar.hasFocus()) ||
            (::centerTransport.isInitialized && centerTransport.hasFocus())

    private fun logFocus(label: String) {
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            Log.i("LUMEN_TV_FOCUS", label)
        }
    }

    private fun buildErrorPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            setPadding(dp(24), dp(18), dp(24), dp(18))
            background = roundedRect(0xEB111315.toInt(), 0x66C5FF63, 1, 18)
            layoutParams = FrameLayout.LayoutParams(
                dp(520),
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
        errorPreviousButton = themedButton(
            if (isLive) "‹  Channel" else "‹  Episode",
            if (isLive) "Try the previous channel" else "Try the previous episode",
            showPlayerControlsOnFocus = false
        ) {
            openPlaylistItem(playlistIndex - 1)
        }
        retryButton = themedButton(
            "Try again",
            "Try this stream again",
            showPlayerControlsOnFocus = false,
            prominent = true
        ) {
            retryAttempt = 0
            retryScheduled = false
            terminalError = false
            errorPanel.visibility = View.GONE
            open()
            showControls(requestTransportFocus = true)
        }
        errorNextButton = themedButton(
            if (isLive) "Channel  ›" else "Episode  ›",
            if (isLive) "Try the next channel" else "Try the next episode",
            showPlayerControlsOnFocus = false
        ) {
            openPlaylistItem(playlistIndex + 1)
        }
        panel.addView(
            errorText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        actions.addView(
            errorPreviousButton,
            LinearLayout.LayoutParams(dp(112), dp(44)).apply { marginEnd = dp(6) }
        )
        actions.addView(
            retryButton,
            LinearLayout.LayoutParams(dp(140), dp(44)).apply {
                marginStart = dp(6)
                marginEnd = dp(6)
            }
        )
        actions.addView(
            errorNextButton,
            LinearLayout.LayoutParams(dp(112), dp(44)).apply { marginStart = dp(6) }
        )
        panel.addView(
            actions,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        updateErrorNavigationUi()
        return panel
    }

    private fun updateErrorNavigationUi() {
        if (!::retryButton.isInitialized) return
        errorPreviousButton.isEnabled = playlistIndex > 0
        errorNextButton.isEnabled = playlistIndex < playlistUrls.lastIndex
        val active = listOf(errorPreviousButton, retryButton, errorNextButton)
            .filter { it.isEnabled }
        active.forEachIndexed { index, button ->
            button.nextFocusLeftId = active.getOrNull(index - 1)?.id ?: button.id
            button.nextFocusRightId = active.getOrNull(index + 1)?.id ?: button.id
            button.nextFocusUpId = button.id
            button.nextFocusDownId = button.id
        }
    }

    private fun moveErrorFocus(forward: Boolean): Boolean {
        val active = listOf(errorPreviousButton, retryButton, errorNextButton)
            .filter { it.visibility == View.VISIBLE && it.isEnabled }
        if (active.isEmpty()) return false
        val current = active.indexOfFirst { it.hasFocus() }.let {
            if (it < 0) active.indexOf(retryButton).coerceAtLeast(0) else it
        }
        val target = (current + if (forward) 1 else -1)
            .coerceIn(0, active.lastIndex)
        active[target].requestFocus()
        return true
    }

    private fun open() {
        terminalError = false
        openedAtMs = SystemClock.elapsedRealtime()
        lastProgressAtMs = openedAtMs
        lastPositionMs = 0L
        hasStarted = false
        hasRenderedVideoFrame = false
        player.stop()
        player.volume = 0f
        player.setMediaItem(buildMediaItem())
        player.playWhenReady = true
        player.prepare()
        showBufferingStatus(if (isLive) "Building live buffer…" else "Opening video…")
    }

    private fun markHealthy(now: Long, position: Long) {
        markProgress(now, position)
        retryAttempt = 0
        retryScheduled = false
        terminalError = false
        errorPanel.visibility = View.GONE
        hideBufferingStatus()
    }

    private fun markProgress(now: Long, position: Long) {
        hasStarted = true
        lastProgressAtMs = now
        lastPositionMs = position
    }

    private fun scheduleRetry(message: String) {
        if (retryScheduled) return
        if (
            Media3PlaybackPolicy.shouldTryAlternate(
                isLive = isLive,
                usingAlternateSource = usingAlternateSource,
                currentUrl = url,
                alternateUrl = alternateUrl
            )
        ) {
            usingAlternateSource = true
            url = alternateUrl
            retryScheduled = true
            hideControls(force = true)
            errorPanel.visibility = View.GONE
            showBufferingStatus("Trying compatible live stream…")
            handler.postDelayed({
                retryScheduled = false
                open()
            }, 500L)
            return
        }
        if (retryAttempt >= RETRY_DELAYS_MS.size) {
            showError(message)
            return
        }
        retryScheduled = true
        hideControls(force = true)
        val delay = RETRY_DELAYS_MS[retryAttempt++]
        errorPanel.visibility = View.GONE
        showBufferingStatus(
            if (isLive) {
                "Reconnecting to live stream · ${retryAttempt}/${RETRY_DELAYS_MS.size}"
            } else {
                "Recovering video · ${retryAttempt}/${RETRY_DELAYS_MS.size}"
            }
        )
        handler.postDelayed({
            retryScheduled = false
            open()
        }, delay)
    }

    private fun selectPreferredSource(index: Int) {
        url = playlistUrls[index]
        alternateUrl = playlistAlternateUrls.getOrNull(index).orEmpty()
        usingAlternateSource = false
    }

    private fun showError(message: String) {
        // Media3 is the preferred Android TV engine because it owns a native
        // SurfaceView. If its bounded source and decoder recovery is exhausted,
        // return control to Flutter so the already bundled mpv engine can try
        // the same item automatically instead of stranding the viewer.
        if (intent.getBooleanExtra(EXTRA_IS_LIVE, false) || hasStarted) {
            hideControls(force = true)
            terminalError = true
            errorPanel.visibility = View.GONE
            handler.removeCallbacks(revealBufferingBadge)
            bufferingBadge.text = "Switching playback engine…"
            bufferingBadge.visibility = View.VISIBLE
            handler.postDelayed({
                returningToEmbeddedEngine = true
                setResult(RESULT_USE_EMBEDDED_ENGINE)
                finish()
            }, 650L)
            return
        }
        hideControls(force = true)
        terminalError = true
        hideBufferingStatus()
        errorText.text = message
        errorPanel.visibility = View.VISIBLE
        updateErrorNavigationUi()
        retryButton.requestFocus()
    }

    override fun finish() {
        if (!returningToEmbeddedEngine && playlistUrls.isNotEmpty()) {
            setResult(
                RESULT_OK,
                Intent().apply {
                    putExtra(EXTRA_LAST_INDEX, playlistIndex)
                    putStringArrayListExtra(
                        EXTRA_PLAYLIST_FAVORITE_KEYS,
                        ArrayList(playlistFavoriteKeys)
                    )
                    putExtra(
                        EXTRA_PLAYLIST_FAVORITE_STATES,
                        playlistFavoriteStates.toBooleanArray()
                    )
                }
            )
        }
        super.finish()
    }

    private fun friendlyError(error: PlaybackException): String {
        val status = responseCode(error)
        return when {
        status == 401 || status == 403 ->
            "The provider rejected this stream. Check the account or device limit."
        status == 404 ->
            "The provider no longer has this stream."
        error.errorCodeName.contains("HTTP", ignoreCase = true) ->
            "The provider could not serve this stream (HTTP ${status ?: "error"})."
        error.errorCodeName.contains("DECOD", ignoreCase = true) ->
            "Android cannot decode this stream format."
        error.errorCodeName.contains("NETWORK", ignoreCase = true) ->
            "The provider could not be reached from this device."
        else -> "The stream did not start in the compatibility player."
        }
    }

    private fun responseCode(error: Throwable): Int? {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is HttpDataSource.InvalidResponseCodeException) {
                return cause.responseCode
            }
            cause = cause.cause
        }
        return null
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (
            event.action == KeyEvent.ACTION_DOWN &&
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        ) {
            Log.i(
                "LUMEN_TV_REMOTE",
                "${KeyEvent.keyCodeToString(event.keyCode)} controls=$controlsVisible " +
                    "focus=${currentFocus?.contentDescription ?: currentFocus?.javaClass?.simpleName}"
            )
        }
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (controlsVisible && !terminalError) {
                hideControls(force = true)
                return true
            }
            finish()
            return true
        }
        if (
            event.action == KeyEvent.ACTION_UP &&
            event.keyCode == heldSeekKeyCode
        ) {
            heldSeekKeyCode = KeyEvent.KEYCODE_UNKNOWN
            heldSeekAnchorMs = 0L
            return true
        }
        if (::errorPanel.isInitialized && errorPanel.visibility == View.VISIBLE) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (event.keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> return moveErrorFocus(false)
                    KeyEvent.KEYCODE_DPAD_RIGHT -> return moveErrorFocus(true)
                }
            }
            return super.dispatchKeyEvent(event)
        }
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_SPACE,
                KeyEvent.KEYCODE_K,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    if (event.repeatCount == 0) togglePlayPause()
                    showControlsFromRemote()
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_PLAY -> {
                    player.play()
                    showControlsFromRemote()
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    player.pause()
                    showControlsFromRemote()
                    return true
                }
                KeyEvent.KEYCODE_J,
                KeyEvent.KEYCODE_MEDIA_REWIND -> {
                    seekFromHeldKey(event, -1)
                    showControlsFromRemote()
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_L,
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                    seekFromHeldKey(event, 1)
                    showControlsFromRemote()
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_S,
                KeyEvent.KEYCODE_MEDIA_STOP -> {
                    if (event.repeatCount == 0) {
                        player.stop()
                        finish()
                    }
                    return true
                }
                KeyEvent.KEYCODE_M -> {
                    if (event.repeatCount == 0) toggleKeyboardMute()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_NUMPAD_ENTER -> if (
                    !controlsVisible || playerView.hasFocus()
                ) {
                    if (event.repeatCount == 0) togglePlayPause()
                    showControlsFromRemote()
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_LEFT -> if (
                    !isLive &&
                    (!controlsVisible || playerView.hasFocus())
                ) {
                    seekFromHeldKey(event, -1)
                    showControls(requestTransportFocus = true)
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT -> if (
                    !isLive &&
                    (!controlsVisible || playerView.hasFocus())
                ) {
                    seekFromHeldKey(event, 1)
                    showControls(requestTransportFocus = true)
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_DPAD_DOWN -> if (!controlsVisible) {
                    // Any first remote press wakes the controller at its
                    // stable central action instead of leaving an invisible
                    // focus owner on the video surface.
                    showControlsFromRemote()
                    return true
                }
            }
        }
        if (
            event.action == KeyEvent.ACTION_DOWN &&
            event.keyCode != KeyEvent.KEYCODE_VOLUME_UP &&
            event.keyCode != KeyEvent.KEYCODE_VOLUME_DOWN &&
            event.keyCode != KeyEvent.KEYCODE_VOLUME_MUTE &&
            !controlsVisible
        ) {
            showControlsFromRemote()
            return true
        }
        if (event.action == KeyEvent.ACTION_DOWN && controlsVisible) {
            scheduleControlsHide()
            when (event.keyCode) {
                KeyEvent.KEYCODE_CHANNEL_UP,
                KeyEvent.KEYCODE_MEDIA_NEXT -> {
                    openPlaylistItem(playlistIndex + 1)
                    return true
                }
                KeyEvent.KEYCODE_CHANNEL_DOWN,
                KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                    openPlaylistItem(playlistIndex - 1)
                    return true
                }
            }
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
