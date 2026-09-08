package com.talhaashraf.lumen

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3PlaybackPolicyTest {
    @Test
    fun balancedLiveBuildsACushionBeforeStarting() {
        val buffers = Media3PlaybackPolicy.buffers(
            isLive = true,
            mode = Media3PlaybackMode.BALANCED
        )

        assertEquals(30_000, buffers.minBufferMs)
        assertEquals(60_000, buffers.maxBufferMs)
        assertEquals(2_000, buffers.bufferForPlaybackMs)
        assertEquals(4_000, buffers.bufferForPlaybackAfterRebufferMs)
        assertEquals(0, buffers.backBufferMs)
        assertFalse(buffers.retainBackBufferFromKeyframe)
    }

    @Test
    fun liveModesExposeIntentionalLatencyStabilityTradeoffs() {
        val stable = Media3PlaybackPolicy.buffers(
            isLive = true,
            mode = Media3PlaybackMode.STABLE
        )
        val lowLatency = Media3PlaybackPolicy.buffers(
            isLive = true,
            mode = Media3PlaybackMode.LOW_LATENCY
        )

        assertEquals(6_000, stable.bufferForPlaybackMs)
        assertEquals(8_000, stable.bufferForPlaybackAfterRebufferMs)
        assertEquals(90_000, stable.maxBufferMs)
        assertEquals(500, lowLatency.bufferForPlaybackMs)
        assertEquals(1_000, lowLatency.bufferForPlaybackAfterRebufferMs)
        assertEquals(20_000, lowLatency.maxBufferMs)
        assertEquals(
            Media3PlaybackMode.LOW_LATENCY,
            Media3PlaybackMode.from("lowLatency")
        )
        assertEquals(
            Media3PlaybackMode.BALANCED,
            Media3PlaybackMode.from("unknown")
        )
    }

    @Test
    fun liveFallsBackOnlyOnceToADifferentAvailableSource() {
        assertTrue(
            Media3PlaybackPolicy.shouldTryAlternate(
                isLive = true,
                usingAlternateSource = false,
                currentUrl = "https://provider.example/live/1.m3u8",
                alternateUrl = "https://provider.example/live/1.ts"
            )
        )
        assertFalse(
            Media3PlaybackPolicy.shouldTryAlternate(
                isLive = true,
                usingAlternateSource = true,
                currentUrl = "https://provider.example/live/1.ts",
                alternateUrl = "https://provider.example/live/1.ts"
            )
        )
        assertFalse(
            Media3PlaybackPolicy.shouldTryAlternate(
                isLive = false,
                usingAlternateSource = false,
                currentUrl = "https://provider.example/movie/1.mp4",
                alternateUrl = "https://provider.example/movie/1.mkv"
            )
        )
    }
}
