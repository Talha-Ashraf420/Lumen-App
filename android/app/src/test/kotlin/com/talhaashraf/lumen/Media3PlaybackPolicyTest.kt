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

    @Test
    fun liveConnectionCopyDistinguishesOpeningFromRecovery() {
        assertEquals(
            "Connecting to live stream…",
            Media3PlaybackPolicy.bufferingLabel(isLive = true, reconnecting = false)
        )
        assertEquals(
            "Reconnecting to live stream…",
            Media3PlaybackPolicy.bufferingLabel(isLive = true, reconnecting = true)
        )
    }

    @Test
    fun televisionSeekFeedbackUsesThePhysicalSeekSide() {
        assertEquals(
            SeekFeedbackSide.LEFT,
            Media3PlaybackPolicy.seekFeedbackSide(-10_000L, isTelevision = true)
        )
        assertEquals(
            SeekFeedbackSide.RIGHT,
            Media3PlaybackPolicy.seekFeedbackSide(10_000L, isTelevision = true)
        )
        assertEquals(
            SeekFeedbackSide.CENTER,
            Media3PlaybackPolicy.seekFeedbackSide(10_000L, isTelevision = false)
        )
    }

    @Test
    fun heldSeekAcceleratesFromSecondsIntoControlledMinuteStages() {
        assertEquals(10_000L, Media3PlaybackPolicy.heldSeekDistanceMs(repeatCount = 0))
        assertEquals(60_000L, Media3PlaybackPolicy.heldSeekDistanceMs(repeatCount = 1))
        assertEquals(60_000L, Media3PlaybackPolicy.heldSeekDistanceMs(repeatCount = 8))
        assertEquals(120_000L, Media3PlaybackPolicy.heldSeekDistanceMs(repeatCount = 9))
        assertEquals(180_000L, Media3PlaybackPolicy.heldSeekDistanceMs(repeatCount = 17))
    }

    @Test
    fun televisionShowsPlaylistAndSeekNavigationForSeries() {
        assertTrue(
            Media3PlaybackPolicy.showPlaylistNavigation(
                isTelevision = true,
                playlistSize = 8
            )
        )
        assertTrue(
            Media3PlaybackPolicy.showSeekNavigation(
                isTelevision = true,
                isLive = false
            )
        )
        assertFalse(
            Media3PlaybackPolicy.showPlaylistNavigation(
                isTelevision = true,
                playlistSize = 1
            )
        )
    }

    @Test
    fun onDemandRemoteWakeReturnsFocusToCentralTransport() {
        assertTrue(
            Media3PlaybackPolicy.focusTransportOnRemoteInput(
                isLive = false,
                controlsVisible = false,
                playerSurfaceFocused = true
            )
        )
        assertTrue(
            Media3PlaybackPolicy.focusTransportOnRemoteInput(
                isLive = false,
                controlsVisible = true,
                playerSurfaceFocused = true
            )
        )
        assertFalse(
            Media3PlaybackPolicy.focusTransportOnRemoteInput(
                isLive = false,
                controlsVisible = true,
                playerSurfaceFocused = false
            )
        )
        assertFalse(
            Media3PlaybackPolicy.focusTransportOnRemoteInput(
                isLive = true,
                controlsVisible = false,
                playerSurfaceFocused = true
            )
        )
    }

    @Test
    fun splitChannelNavigationSkipsTheOtherVisibleChannel() {
        assertEquals(
            4,
            Media3PlaybackPolicy.nextSplitIndex(
                currentIndex = 2,
                blockedIndex = 3,
                direction = 1,
                itemCount = 8
            )
        )
        assertEquals(
            1,
            Media3PlaybackPolicy.nextSplitIndex(
                currentIndex = 3,
                blockedIndex = 2,
                direction = -1,
                itemCount = 8
            )
        )
    }

    @Test
    fun splitChannelNavigationStopsAtPlaylistEdges() {
        assertEquals(
            null,
            Media3PlaybackPolicy.nextSplitIndex(0, 1, -1, 4)
        )
        assertEquals(
            null,
            Media3PlaybackPolicy.nextSplitIndex(3, 2, 1, 4)
        )
        assertEquals(
            null,
            Media3PlaybackPolicy.nextSplitIndex(1, 0, 0, 4)
        )
    }
}
