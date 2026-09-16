package com.talhaashraf.lumen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.LinkedHashMap
import java.util.concurrent.Executors
import kotlin.math.min

/**
 * Runs user-started downloads after the Flutter Activity has gone away.
 * Provider URLs live only in this process's memory, never in JobScheduler,
 * WorkManager, notifications, logs or Android shared preferences. If Android
 * kills the service, the partial file is kept and Flutter restores it paused.
 */
class DownloadTransferService : Service() {
    companion object {
        private const val ACTION_ENQUEUE = "com.talhaashraf.lumen.download.ENQUEUE"
        private const val CHANNEL_ID = "lumen_downloads"
        private const val NOTIFICATION_ID = 7321
        private val KEY_PATTERN = Regex("^[a-f0-9]{64}$")

        @Volatile private var running: DownloadTransferService? = null

        fun enqueue(context: Context, args: Map<*, *>): Boolean {
            val key = args["key"] as? String ?: return false
            val url = args["url"] as? String ?: return false
            val path = args["path"] as? String ?: return false
            val protocol = try { URL(url).protocol } catch (_: Exception) { return false }
            if (!KEY_PATTERN.matches(key) || (protocol != "http" && protocol != "https")) return false
            val intent = Intent(context, DownloadTransferService::class.java).apply {
                action = ACTION_ENQUEUE
                putExtra("key", key)
                putExtra("url", url)
                putExtra("path", path)
                putExtra("title", (args["title"] as? String ?: "Media download").take(80))
            }
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
            return true
        }

        fun snapshot(): List<Map<String, Any>> = running?.snapshotLocal() ?: emptyList()
        fun pause(key: String) { running?.stopTask(key, cancel = false) }
        fun cancel(key: String) { running?.stopTask(key, cancel = true) }
        fun pauseAll() { running?.pauseAllLocal() }
    }

    private data class Transfer(
        val key: String,
        val url: String,
        val file: File,
        val title: String,
        @Volatile var status: String = "queued",
        @Volatile var received: Long = 0,
        @Volatile var total: Long = 0,
        @Volatile var stopped: Boolean = false,
        @Volatile var cancelled: Boolean = false,
        @Volatile var connection: HttpURLConnection? = null,
        @Volatile var error: String = "",
    )

    private val lock = Any()
    private val transfers = LinkedHashMap<String, Transfer>()
    private val worker = Executors.newSingleThreadExecutor()
    private var processing = false
    private var latestStartId = 0
    private var lastNotificationAt = 0L
    private var foregroundStarted = false

    override fun onCreate() {
        super.onCreate()
        running = this
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Lumen downloads", NotificationManager.IMPORTANCE_LOW)
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        synchronized(lock) { latestStartId = startId }
        // startForeground must happen promptly even if validation rejects a job.
        showNotification(null)
        if (intent?.action == ACTION_ENQUEUE) {
            val key = intent.getStringExtra("key")
            val url = intent.getStringExtra("url")
            val path = intent.getStringExtra("path")
            val title = intent.getStringExtra("title") ?: "Media download"
            val file = path?.let { File(it).canonicalFile }
            if (key != null && url != null && file != null &&
                validDestination(file) && KEY_PATTERN.matches(key)) {
                synchronized(lock) {
                    if (!transfers.containsKey(key)) {
                        marker(key).delete()
                        failureMarker(key).delete()
                        transfers[key] = Transfer(key, url, file, title)
                    }
                }
                pump()
            } else {
                stopIfIdle(startId)
            }
        } else {
            stopIfIdle(startId)
        }
        return START_NOT_STICKY
    }

    private fun validDestination(file: File): Boolean {
        val roots = listOfNotNull(filesDir, getExternalFilesDir(null))
        return roots.any { root ->
            file.path.startsWith(root.canonicalPath + File.separator)
        }
    }

    private fun snapshotLocal(): List<Map<String, Any>> = synchronized(lock) {
        transfers.values.map { task ->
            mapOf(
                "key" to task.key,
                "status" to task.status,
                "received" to task.received,
                "total" to task.total,
                "error" to task.error,
            )
        }
    }

    private fun stopTask(key: String, cancel: Boolean) {
        synchronized(lock) {
            val task = transfers[key] ?: return
            task.stopped = true
            task.cancelled = cancel
            task.connection?.disconnect()
            if (task.status == "queued") {
                transfers.remove(key)
                if (cancel) {
                    task.file.delete()
                    marker(key).delete()
                }
            }
        }
        pump()
    }

    private fun pauseAllLocal() {
        for (key in synchronized(lock) { transfers.keys.toList() }) stopTask(key, false)
    }

    private fun stopIfIdle(startId: Int) {
        val idle = synchronized(lock) { !processing && transfers.isEmpty() }
        if (idle) stopSelfResult(startId)
    }

    private fun pump() {
        synchronized(lock) {
            if (processing) return
            processing = true
        }
        worker.execute {
            try {
                while (true) {
                    val next = synchronized(lock) {
                        transfers.values.firstOrNull { it.status == "queued" && !it.stopped }
                    } ?: break
                    runTransfer(next)
                    synchronized(lock) { transfers.remove(next.key) }
                }
            } finally {
                synchronized(lock) { processing = false }
                // Enqueue can race with the end of the worker.
                val stopId = synchronized(lock) {
                    if (transfers.values.any { it.status == "queued" && !it.stopped }) null
                    else latestStartId
                }
                if (stopId == null) pump()
                else stopSelfResult(stopId)
            }
        }
    }

    private class PermanentFailure(message: String) : Exception(message)

    private fun runTransfer(task: Transfer) {
        task.status = "downloading"
        showNotification(task)
        task.file.parentFile?.mkdirs()
        var attempt = 0
        while (!task.stopped && attempt < 8) {
            attempt++
            try {
                transferOnce(task)
                if (task.stopped) break
                val done = marker(task.key)
                done.parentFile?.mkdirs()
                FileOutputStream(done).use { output ->
                    output.write(task.file.length().toString().toByteArray(Charsets.UTF_8))
                    output.fd.sync()
                }
                failureMarker(task.key).delete()
                task.status = "completed"
                return
            } catch (failure: Exception) {
                if (task.stopped) break
                if (failure is PermanentFailure || attempt >= 8) {
                    task.status = "failed"
                    task.error = when (failure) {
                        is PermanentFailure -> failure.message ?: "Provider rejected the download."
                        else -> "Connection interrupted. Resume to try again."
                    }
                    failureMarker(task.key).apply {
                        parentFile?.mkdirs()
                        writeText(task.error)
                    }
                    return
                }
                // Slow/unstable connections keep the partial file. A new request
                // starts at its exact byte length rather than starting over.
                val delay = min(30_000L, 1_000L shl min(attempt, 5))
                var waited = 0L
                while (waited < delay && !task.stopped) {
                    SystemClock.sleep(250)
                    waited += 250
                }
            } finally {
                task.connection?.disconnect()
                task.connection = null
            }
        }
        task.status = if (task.cancelled) "cancelled" else "paused"
        if (task.cancelled) {
            task.file.delete()
            marker(task.key).delete()
            failureMarker(task.key).delete()
        }
    }

    private fun transferOnce(task: Transfer) {
        val existing = if (task.file.exists()) task.file.length() else 0L
        val connection = (URL(task.url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 20_000
            readTimeout = 45_000
            setRequestProperty("User-Agent", "VLC/3.0.20 LibVLC/3.0.20")
            if (existing > 0) setRequestProperty("Range", "bytes=$existing-")
        }
        task.connection = connection
        val code = connection.responseCode
        if (code == 416 && existing > 0) {
            val reportedTotal = Regex("bytes \\*/(\\d+)")
                .matchEntire(connection.getHeaderField("Content-Range") ?: "")
                ?.groupValues?.get(1)?.toLongOrNull()
            if (reportedTotal == existing) {
                task.received = existing
                task.total = existing
                return
            }
            task.file.delete()
            task.received = 0
            task.total = 0
            throw Exception("Saved byte range is no longer available")
        }
        if (code != 200 && code != 206) {
            if (code in listOf(400, 401, 403, 404, 410)) {
                throw PermanentFailure("Provider returned HTTP $code.")
            }
            throw Exception("HTTP $code")
        }
        val range = if (code == 206) {
            Regex("bytes (\\d+)-(\\d+)/(\\d+|\\*)")
                .matchEntire(connection.getHeaderField("Content-Range") ?: "")
        } else null
        if (code == 206 && (range == null || range.groupValues[1].toLong() != existing)) {
            // Never append the wrong byte range to a partial video.
            task.file.delete()
            task.received = 0
            task.total = 0
            throw Exception("Invalid provider byte range")
        }
        val append = existing > 0 && code == 206
        val start = if (append) existing else 0L
        val length = connection.contentLengthLong.coerceAtLeast(0)
        val rangeTotal = range?.groupValues?.get(3)?.toLongOrNull()
        task.total = rangeTotal ?: if (length > 0) start + length else 0
        task.received = start
        connection.inputStream.use { input ->
            FileOutputStream(task.file, append).use { output ->
                val buffer = ByteArray(64 * 1024)
                while (!task.stopped) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    task.received += count
                    if (SystemClock.elapsedRealtime() - lastNotificationAt > 700) {
                        showNotification(task)
                    }
                }
                output.fd.sync()
            }
        }
        if (task.stopped) return
        if (task.total > 0 && task.received != task.total) {
            throw Exception("Provider ended response early")
        }
    }

    private fun marker(key: String) = File(File(filesDir, "lumen-download-markers"), "$key.done")
    private fun failureMarker(key: String) = File(File(filesDir, "lumen-download-markers"), "$key.failed")

    private fun showNotification(task: Transfer?) {
        lastNotificationAt = SystemClock.elapsedRealtime()
        val intent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val progress = task?.let {
            if (it.total > 0) ((it.received * 100) / it.total).toInt().coerceIn(0, 100)
            else 0
        } ?: 0
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Lumen download")
            .setContentText(task?.title ?: "Preparing download")
            .setContentIntent(pending)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, progress, (task?.total ?: 0) <= 0)
            .build()
        if (!foregroundStarted) {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else startForeground(NOTIFICATION_ID, notification)
            foregroundStarted = true
        } else {
            getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        running = null
        synchronized(lock) {
            transfers.values.forEach {
                it.stopped = true
                it.connection?.disconnect()
            }
        }
        worker.shutdownNow()
        super.onDestroy()
    }
}
