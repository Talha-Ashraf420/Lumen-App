package com.talhaashraf.lumen

import android.net.Uri
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.EOFException
import java.io.IOException

/**
 * Joins short, successful HTTP responses from endless MPEG-TS endpoints.
 *
 * Some IPTV servers intentionally close a live response after only a few
 * seconds. Exposing that EOF to Media3 ends the item and discards its useful
 * forward buffer. This wrapper closes and reopens the same non-seekable URL on
 * the loader thread before Media3 sees EOF, so playback can consume the data
 * already buffered while the next response starts.
 */
internal class LiveReconnectDataSource(
    private val upstreamFactory: DataSource.Factory,
    private val reconnectDelayMs: Long,
    private val shouldReconnectAtEof: () -> Boolean,
    private val maxEmptyResponses: Int = 3
) : DataSource {
    class Factory(
        private val upstreamFactory: DataSource.Factory,
        private val reconnectDelayMs: Long,
        private val shouldReconnectAtEof: () -> Boolean
    ) : DataSource.Factory {
        override fun createDataSource(): DataSource = LiveReconnectDataSource(
            upstreamFactory = upstreamFactory,
            reconnectDelayMs = reconnectDelayMs,
            shouldReconnectAtEof = shouldReconnectAtEof
        )
    }

    private val listeners = mutableListOf<TransferListener>()
    private var upstream = createUpstream()
    private var originalDataSpec: DataSpec? = null
    private var opened = false
    private var bytesInResponse = 0L
    private var consecutiveEmptyResponses = 0

    override fun addTransferListener(transferListener: TransferListener) {
        listeners += transferListener
        upstream.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        originalDataSpec = dataSpec
        bytesInResponse = 0L
        consecutiveEmptyResponses = 0
        return openUpstream(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        while (true) {
            val read = upstream.read(buffer, offset, length)
            if (read != C.RESULT_END_OF_INPUT) {
                if (read > 0) bytesInResponse += read
                return read
            }

            // HLS playlists and their media segments must end normally. Only
            // concatenate EOFs while the top-level item is a raw live TS URL.
            if (!shouldReconnectAtEof()) return C.RESULT_END_OF_INPUT

            if (bytesInResponse == 0L) {
                consecutiveEmptyResponses += 1
                if (consecutiveEmptyResponses > maxEmptyResponses) {
                    throw EOFException("Live endpoint returned repeated empty responses")
                }
            } else {
                consecutiveEmptyResponses = 0
            }

            closeUpstream()
            if (reconnectDelayMs > 0L) SystemClock.sleep(reconnectDelayMs)
            upstream = createUpstream()
            bytesInResponse = 0L
            openUpstream(
                originalDataSpec
                    ?: throw IOException("Live endpoint was not opened")
            )
        }
    }

    override fun getUri(): Uri? = upstream.uri

    override fun getResponseHeaders(): Map<String, List<String>> =
        upstream.responseHeaders

    override fun close() {
        closeUpstream()
        originalDataSpec = null
        bytesInResponse = 0L
        consecutiveEmptyResponses = 0
    }

    private fun createUpstream(): DataSource =
        upstreamFactory.createDataSource().also { source ->
            listeners.forEach(source::addTransferListener)
        }

    private fun openUpstream(dataSpec: DataSpec): Long {
        val length = upstream.open(dataSpec)
        opened = true
        return length
    }

    private fun closeUpstream() {
        if (!opened) return
        try {
            upstream.close()
        } finally {
            opened = false
        }
    }
}
