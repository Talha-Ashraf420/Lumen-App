package com.talhaashraf.lumen

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3PlaybackPolicyTest {
    @Test
    fun liveBuildsALargeCushionButStartsAndResumesQuickly() {
        val buffers = Media3PlaybackPolicy.buffers(isLive = true)

        assertEquals(40_000, buffers.minBufferMs)
        assertEquals(90_000, buffers.maxBufferMs)
        assertEquals(1_000, buffers.bufferForPlaybackMs)
        assertEquals(2_000, buffers.bufferForPlaybackAfterRebufferMs)
        assertEquals(0, buffers.backBufferMs)
        assertFalse(buffers.retainBackBufferFromKeyframe)
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
