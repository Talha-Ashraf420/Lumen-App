package com.talhaashraf.lumen

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
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
        const val EXTRA_HEADERS = "headers"
        const val EXTRA_PLAYLIST_URLS = "playlistUrls"
        const val EXTRA_PLAYLIST_TITLES = "playlistTitles"
        const val EXTRA_INITIAL_INDEX = "initialIndex"

        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 60_000
        private const val STARTUP_TIMEOUT_MS = 60_000L
        private const val FIRST_VIDEO_FRAME_TIMEOUT_MS = 15_000L
        private const val LIVE_STALL_TIMEOUT_MS = 20_000L
        private const val WATCHDOG_INTERVAL_MS = 2_000L
        private const val CONTROLS_TIMEOUT_MS = 5_000L
        private const val PROGRESS_INTERVAL_MS = 500L
        private const val SEEK_INCREMENT_MS = 10_000L
        private const val SUBTITLE_REQUEST_CODE = 6205
        private val RETRY_DELAYS_MS = longArrayOf(1_000, 3_000, 5_000)
    }

    private lateinit var player: ExoPlayer
    private lateinit var playerView: PlayerView
    private lateinit var titleBar: View
    private lateinit var controlsBar: View
    private lateinit var backButton: Button
    private lateinit var titleText: TextView
    private lateinit var previousButton: Button
    private lateinit var nextButton: Button
    private lateinit var rewindButton: Button
    private lateinit var playPauseButton: Button
    private lateinit var forwardButton: Button
    private lateinit var subtitleButton: Button
    private lateinit var audioButton: Button
    private lateinit var progressBar: SeekBar
    private lateinit var positionText: TextView
    private lateinit var durationText: TextView
    private val transportButtons = mutableListOf<Button>()
    private lateinit var errorPanel: LinearLayout
    private lateinit var errorText: TextView
    private lateinit var errorPreviousButton: Button
    private lateinit var retryButton: Button
    private lateinit var errorNextButton: Button
    private val handler = Handler(Looper.getMainLooper())
    private var retryAttempt = 0
    private var retryScheduled = false
    private var terminalError = false
    private var url = ""
    private var isLive = false
    private var playlistUrls = listOf<String>()
    private var playlistTitles = listOf<String>()
    private var playlistIndex = 0
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

    private data class TrackChoice(
        val group: Tracks.Group,
        val trackIndex: Int,
        val label: String
    )

    private val hideControls = Runnable { hideControls() }
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
        playlistUrls = intent.getStringArrayListExtra(EXTRA_PLAYLIST_URLS)
            ?.filter { it.isNotBlank() }
            .orEmpty()
        playlistTitles = intent.getStringArrayListExtra(EXTRA_PLAYLIST_TITLES)
            .orEmpty()
        if (playlistUrls.isEmpty()) {
            playlistUrls = listOf(url)
            playlistTitles = listOf(intent.getStringExtra(EXTRA_TITLE).orEmpty())
        }
        playlistIndex = intent.getIntExtra(EXTRA_INITIAL_INDEX, 0)
            .coerceIn(0, playlistUrls.lastIndex)
        url = playlistUrls[playlistIndex]
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
        errorPanel = buildErrorPanel()
        root.addView(errorPanel)
        setContentView(root)

        player = buildPlayer()
        playerView.player = player
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                updateTransportUi()
                when (state) {
                    Player.STATE_READY -> {
                        retryScheduled = false
                        errorPanel.visibility = View.GONE
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
                // Start movies and channels in a clean cinema view. The first
                // remote press reveals the complete transport and title bar.
                hideControls(force = true)
            }
        })
        updateNavigationUi()
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

        // Live keeps a responsive window; VOD builds a substantially deeper
        // cushion to absorb Wi-Fi/provider jitter. In particular, do not resume
        // a movie immediately after collecting only a few seconds: that causes
        // a fill/drain/rebuffer loop on bursty IPTV providers.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                if (isLive) 18_000 else 45_000,
                if (isLive) 40_000 else 90_000,
                if (isLive) 5_000 else 10_000,
                if (isLive) 8_000 else 18_000
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        // DefaultDataSource delegates network requests to the hardened HTTP
        // factory and content:// subtitle files to Android's content resolver.
        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(DefaultDataSource.Factory(this, http))
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

    private fun buildTitleBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(24), dp(18), dp(24), dp(18))
            setBackgroundColor(0xCC0B0D0B.toInt())
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP
            )
        }
        backButton = themedButton("←", "Back to Lumen") { finish() }.apply {
            textSize = 22f
        }
        titleText = TextView(this).apply {
            text = playlistTitles.getOrNull(playlistIndex).orEmpty()
            textSize = 20f
            setTextColor(Color.WHITE)
            maxLines = 1
            layoutParams = LinearLayout.LayoutParams(0, dp(52), 1f).apply {
                marginStart = dp(18)
                marginEnd = dp(18)
            }
            gravity = Gravity.CENTER_VERTICAL
        }
        val kind = TextView(this).apply {
            text = if (isLive) "●  LIVE" else "LUMEN"
            textSize = 13f
            setTextColor(0xFFC5FF63.toInt())
            gravity = Gravity.CENTER
            setPadding(dp(16), 0, dp(16), 0)
        }
        bar.addView(backButton, LinearLayout.LayoutParams(dp(64), dp(52)))
        bar.addView(titleText)
        bar.addView(kind, LinearLayout.LayoutParams(dp(112), dp(52)))
        return bar
    }

    private fun buildControlsBar(): View {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(36), dp(18), dp(36), dp(24))
            setBackgroundColor(0xDD0B0D0B.toInt())
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
            progressTintList = ColorStateList.valueOf(0xFFC5FF63.toInt())
            progressBackgroundTintList = ColorStateList.valueOf(0x667F877D)
            thumbTintList = ColorStateList.valueOf(0xFFC5FF63.toInt())
            contentDescription = "Playback position"
            setOnFocusChangeListener { view, focused ->
                view.animate()
                    .scaleY(if (focused) 1.35f else 1f)
                    .setDuration(100L)
                    .start()
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
        progressRow.addView(positionText, LinearLayout.LayoutParams(dp(74), dp(36)))
        progressRow.addView(
            progressBar,
            LinearLayout.LayoutParams(0, dp(36), 1f).apply {
                marginStart = dp(12)
                marginEnd = dp(12)
            }
        )
        progressRow.addView(durationText, LinearLayout.LayoutParams(dp(74), dp(36)))

        val transport = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        }
        previousButton = themedButton(
            if (isLive) "‹  Channel" else "‹  Episode",
            if (isLive) "Previous channel" else "Previous episode"
        ) { openPlaylistItem(playlistIndex - 1) }
        rewindButton = themedButton("↶ 10s", "Rewind 10 seconds") {
            seekBy(-SEEK_INCREMENT_MS)
        }.apply { visibility = if (isLive) View.GONE else View.VISIBLE }
        playPauseButton = themedButton("Pause", "Pause playback") {
            togglePlayPause()
        }.apply { textSize = 16f }
        forwardButton = themedButton("10s ↷", "Fast forward 10 seconds") {
            seekBy(SEEK_INCREMENT_MS)
        }.apply { visibility = if (isLive) View.GONE else View.VISIBLE }
        nextButton = themedButton(
            if (isLive) "Channel  ›" else "Episode  ›",
            if (isLive) "Next channel" else "Next episode"
        ) { openPlaylistItem(playlistIndex + 1) }
        subtitleButton = themedButton("CC / Add", "Choose or add subtitles") {
            showSubtitleDialog()
        }.apply { isEnabled = !isLive }
        audioButton = themedButton("Audio", "Choose audio track") {
            showTrackDialog(C.TRACK_TYPE_AUDIO, "Audio", allowOff = false)
        }.apply { isEnabled = false }

        transportButtons += listOf(
            previousButton,
            rewindButton,
            playPauseButton,
            forwardButton,
            nextButton,
            subtitleButton,
            audioButton
        )
        transport.addView(previousButton, transportParams(dp(132)))
        transport.addView(rewindButton, transportParams(dp(92)))
        transport.addView(playPauseButton, transportParams(dp(116)))
        transport.addView(forwardButton, transportParams(dp(92)))
        transport.addView(nextButton, transportParams(dp(132)))
        transport.addView(subtitleButton, transportParams(dp(110)))
        transport.addView(audioButton, transportParams(dp(96)))
        panel.addView(
            progressRow,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        panel.addView(
            transport,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        return panel
    }

    private fun playerTimeText(): TextView = TextView(this).apply {
        textSize = 13f
        setTextColor(0xFFD8DDD5.toInt())
        gravity = Gravity.CENTER
        maxLines = 1
    }

    private fun transportParams(width: Int): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(width, dp(56)).apply {
            marginStart = dp(6)
            marginEnd = dp(6)
        }

    private fun themedButton(
        label: String,
        description: String,
        showPlayerControlsOnFocus: Boolean = true,
        onClick: () -> Unit
    ): Button = Button(this).apply {
        id = View.generateViewId()
        text = label
        contentDescription = description
        textSize = 13f
        isAllCaps = false
        isFocusable = true
        setPadding(dp(12), 0, dp(12), 0)
        background = buttonBackground()
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
                    Color.WHITE
                )
            )
        )
        setOnFocusChangeListener { view, focused ->
            if (focused && showPlayerControlsOnFocus) showControls()
            view.animate()
                .scaleX(if (focused) 1.045f else 1f)
                .scaleY(if (focused) 1.045f else 1f)
                .setDuration(120L)
                .start()
            view.elevation = if (focused) dp(10).toFloat() else 0f
        }
        setOnClickListener {
            onClick()
            showControls()
        }
    }

    private fun buttonBackground(): StateListDrawable = StateListDrawable().apply {
        addState(
            intArrayOf(-android.R.attr.state_enabled),
            roundedRect(0x55262B24, 0x334F554D, 1)
        )
        addState(
            intArrayOf(android.R.attr.state_focused),
            roundedRect(0xFFC5FF63.toInt(), Color.WHITE, 3)
        )
        addState(
            intArrayOf(android.R.attr.state_pressed),
            roundedRect(0xFFE0FFAA.toInt(), Color.WHITE, 2)
        )
        addState(intArrayOf(), roundedRect(0xDD1A1E1A.toInt(), 0xFF596157.toInt(), 1))
    }

    private fun roundedRect(fill: Int, stroke: Int, strokeWidth: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(12).toFloat()
            setColor(fill)
            setStroke(dp(strokeWidth), stroke)
        }

    private fun updateNavigationUi() {
        if (!::previousButton.isInitialized) return
        previousButton.isEnabled = playlistIndex > 0
        nextButton.isEnabled = playlistIndex < playlistUrls.lastIndex
        titleText.text = playlistTitles.getOrNull(playlistIndex)
            ?.takeIf { it.isNotBlank() }
            ?: if (isLive) "Live channel" else "Episode"
        updateFocusGraph()
        updateErrorNavigationUi()
    }

    private fun updateFocusGraph() {
        if (!::backButton.isInitialized || !::playPauseButton.isInitialized) return
        val active = transportButtons.filter {
            it.visibility == View.VISIBLE && it.isEnabled
        }
        active.forEachIndexed { index, button ->
            button.nextFocusLeftId = active.getOrNull(index - 1)?.id ?: button.id
            button.nextFocusRightId = active.getOrNull(index + 1)?.id ?: button.id
            button.nextFocusUpId = if (progressBar.visibility == View.VISIBLE) {
                progressBar.id
            } else {
                backButton.id
            }
            button.nextFocusDownId = button.id
        }
        backButton.nextFocusLeftId = backButton.id
        backButton.nextFocusRightId = backButton.id
        backButton.nextFocusUpId = backButton.id
        backButton.nextFocusDownId = playPauseButton.id
        if (progressBar.visibility == View.VISIBLE) {
            progressBar.nextFocusUpId = backButton.id
            progressBar.nextFocusDownId = playPauseButton.id
        }
    }

    private fun openPlaylistItem(index: Int) {
        if (index !in playlistUrls.indices || index == playlistIndex) return
        val movingForward = index > playlistIndex
        retryAttempt = 0
        retryScheduled = false
        terminalError = false
        playlistIndex = index
        url = playlistUrls[index]
        externalSubtitleUri = null
        externalSubtitleName = ""
        updateNavigationUi()
        open()
        showControls()
        when {
            movingForward && nextButton.isEnabled -> nextButton.requestFocus()
            !movingForward && previousButton.isEnabled -> previousButton.requestFocus()
            nextButton.isEnabled -> nextButton.requestFocus()
            previousButton.isEnabled -> previousButton.requestFocus()
            else -> playPauseButton.requestFocus()
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

    private fun updateTransportUi() {
        if (!::playPauseButton.isInitialized || !::player.isInitialized) return
        val playing = player.isPlaying
        playPauseButton.text = if (playing) "Pause" else "Play"
        playPauseButton.contentDescription = if (playing) {
            "Pause playback"
        } else {
            "Play"
        }
    }

    private fun updateTrackButtons(tracks: Tracks = player.currentTracks) {
        if (!::subtitleButton.isInitialized || !::audioButton.isInitialized) return
        val subtitleCount = trackChoices(tracks, C.TRACK_TYPE_TEXT).size
        val audioCount = trackChoices(tracks, C.TRACK_TYPE_AUDIO).size
        // Movies can always import a local subtitle, even when the stream has
        // no embedded text tracks. Live keeps the button only for embedded CC.
        subtitleButton.isEnabled = !isLive || subtitleCount > 0
        audioButton.isEnabled = audioCount > 1
        subtitleButton.text = if (externalSubtitleUri != null) {
            "CC Added"
        } else if (
            player.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
        ) {
            "CC Off"
        } else {
            "CC / Add"
        }
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
                choices += TrackChoice(
                    group = group,
                    trackIndex = index,
                    label = details.joinToString(" · ").ifBlank {
                        if (type == C.TRACK_TYPE_AUDIO) {
                            "Audio ${choices.size + 1}"
                        } else {
                            "Subtitle ${choices.size + 1}"
                        }
                    }
                )
            }
        }
        return choices
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
                        player.trackSelectionParameters =
                            player.trackSelectionParameters
                                .buildUpon()
                                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                                .build()
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
        val returnFocus = if (type == C.TRACK_TYPE_TEXT) subtitleButton else audioButton
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
            isLive ||
            !::player.isInitialized ||
            !::progressBar.isInitialized ||
            changingProgress
        ) return
        val duration = player.duration
        val position = player.currentPosition.coerceAtLeast(0L)
        changingProgress = true
        if (duration > 0L) {
            val boundedDuration = duration.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            progressBar.max = boundedDuration
            progressBar.progress = position.coerceAtMost(duration)
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
        if (terminalError || !::controlsBar.isInitialized) return
        controlsVisible = true
        titleBar.visibility = View.VISIBLE
        controlsBar.visibility = View.VISIBLE
        updateTransportUi()
        updateProgressUi()
        scheduleControlsHide()
        if (requestTransportFocus) {
            playPauseButton.post { playPauseButton.requestFocus() }
        }
    }

    private fun scheduleControlsHide() {
        handler.removeCallbacks(hideControls)
        if (::player.isInitialized && player.isPlaying && !terminalError) {
            handler.postDelayed(hideControls, CONTROLS_TIMEOUT_MS)
        }
    }

    private fun hideControls(force: Boolean = false) {
        if (!::controlsBar.isInitialized || terminalError) return
        if (!force && (!::player.isInitialized || !player.isPlaying)) return
        handler.removeCallbacks(hideControls)
        controlsVisible = false
        titleBar.visibility = View.GONE
        controlsBar.visibility = View.GONE
        playerView.requestFocus()
    }

    private fun buildErrorPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            setPadding(dp(28), dp(24), dp(28), dp(24))
            setBackgroundColor(0xEE111315.toInt())
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            ).apply {
                setMargins(dp(24), dp(24), dp(24), dp(24))
            }
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
            showPlayerControlsOnFocus = false
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
            LinearLayout.LayoutParams(dp(156), dp(52)).apply { marginEnd = dp(8) }
        )
        actions.addView(
            retryButton,
            LinearLayout.LayoutParams(dp(180), dp(52)).apply {
                marginStart = dp(8)
                marginEnd = dp(8)
            }
        )
        actions.addView(
            errorNextButton,
            LinearLayout.LayoutParams(dp(156), dp(52)).apply { marginStart = dp(8) }
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
    }

    private fun markHealthy(now: Long, position: Long) {
        markProgress(now, position)
        retryAttempt = 0
        retryScheduled = false
        terminalError = false
        errorPanel.visibility = View.GONE
    }

    private fun markProgress(now: Long, position: Long) {
        hasStarted = true
        lastProgressAtMs = now
        lastPositionMs = position
    }

    private fun scheduleRetry(message: String) {
        if (retryScheduled) return
        if (retryAttempt >= RETRY_DELAYS_MS.size) {
            showError(message)
            return
        }
        retryScheduled = true
        hideControls(force = true)
        val delay = RETRY_DELAYS_MS[retryAttempt++]
        errorText.text = "$message\nRetrying ${retryAttempt}/${RETRY_DELAYS_MS.size}…"
        errorPanel.visibility = View.VISIBLE
        updateErrorNavigationUi()
        retryButton.requestFocus()
        handler.postDelayed({
            retryScheduled = false
            errorPanel.visibility = View.GONE
            open()
        }, delay)
    }

    private fun showError(message: String) {
        hideControls(force = true)
        terminalError = true
        errorText.text = message
        errorPanel.visibility = View.VISIBLE
        updateErrorNavigationUi()
        retryButton.requestFocus()
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
        if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_BACK) {
            finish()
            return true
        }
        if (::errorPanel.isInitialized && errorPanel.visibility == View.VISIBLE) {
            return super.dispatchKeyEvent(event)
        }
        if (event.action == KeyEvent.ACTION_DOWN) {
            val alphabeticKeyboard =
                event.device?.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC
            when (event.keyCode) {
                KeyEvent.KEYCODE_SPACE,
                KeyEvent.KEYCODE_K,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    if (event.repeatCount == 0) togglePlayPause()
                    showControls(requestTransportFocus = false)
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_PLAY -> {
                    player.play()
                    showControls(requestTransportFocus = false)
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    player.pause()
                    showControls(requestTransportFocus = false)
                    return true
                }
                KeyEvent.KEYCODE_J,
                KeyEvent.KEYCODE_MEDIA_REWIND -> {
                    seekBy(-SEEK_INCREMENT_MS)
                    showControls(requestTransportFocus = false)
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_L,
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                    seekBy(SEEK_INCREMENT_MS)
                    showControls(requestTransportFocus = false)
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
                KeyEvent.KEYCODE_DPAD_LEFT -> if (alphabeticKeyboard) {
                    seekBy(-SEEK_INCREMENT_MS)
                    showControls(requestTransportFocus = false)
                    scheduleControlsHide()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT -> if (alphabeticKeyboard) {
                    seekBy(SEEK_INCREMENT_MS)
                    showControls(requestTransportFocus = false)
                    scheduleControlsHide()
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
            showControls(requestTransportFocus = true)
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
