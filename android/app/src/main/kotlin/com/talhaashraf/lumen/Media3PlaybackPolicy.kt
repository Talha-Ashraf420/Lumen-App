package com.talhaashraf.lumen

internal data class Media3BufferDurations(
    val minBufferMs: Int,
    val maxBufferMs: Int,
    val bufferForPlaybackMs: Int,
    val bufferForPlaybackAfterRebufferMs: Int,
    val backBufferMs: Int,
    val retainBackBufferFromKeyframe: Boolean
)

/**
 * Buffer and source-fallback rules kept independent from the Android Activity
 * so the behavior can be covered by fast JVM tests.
 */
internal object Media3PlaybackPolicy {
    private val live = Media3BufferDurations(
        minBufferMs = 40_000,
        maxBufferMs = 90_000,
        bufferForPlaybackMs = 1_000,
        bufferForPlaybackAfterRebufferMs = 2_000,
        backBufferMs = 0,
        retainBackBufferFromKeyframe = false
    )
    private val onDemand = Media3BufferDurations(
        minBufferMs = 45_000,
        maxBufferMs = 120_000,
        bufferForPlaybackMs = 10_000,
        bufferForPlaybackAfterRebufferMs = 22_000,
        backBufferMs = 15_000,
        retainBackBufferFromKeyframe = true
    )

    fun buffers(isLive: Boolean): Media3BufferDurations =
        if (isLive) live else onDemand

    fun shouldTryAlternate(
        isLive: Boolean,
        usingAlternateSource: Boolean,
        currentUrl: String,
        alternateUrl: String
    ): Boolean =
        isLive &&
            !usingAlternateSource &&
            alternateUrl.isNotBlank() &&
            alternateUrl != currentUrl
}
