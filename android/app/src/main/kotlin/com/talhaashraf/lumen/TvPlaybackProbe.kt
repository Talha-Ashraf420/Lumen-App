package com.talhaashraf.lumen

import android.content.Context
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** A bounded, private Media3 trace for the separately packaged reviewer build. */
internal object TvPlaybackProbe {
    private const val PREFS = "tv_playback_probe"
    private const val REPORT = "report"
    private const val MAX_EVENTS = 80
    private var startedAt = 0L

    fun enabled(context: Context): Boolean =
        context.packageName == "com.talhaashraf.lumen.test"

    fun begin(context: Context, isLive: Boolean, mode: String) {
        if (!enabled(context)) return
        startedAt = SystemClock.elapsedRealtime()
        val report = JSONObject()
            .put("report_id", UUID.randomUUID().toString().take(8))
            .put("live", isLive)
            .put("mode", mode.take(24))
            .put("events", JSONArray())
        save(context, report)
        event(context, "opened")
    }

    fun event(
        context: Context,
        name: String,
        detail: String? = null,
        value: Int? = null,
    ) {
        if (!enabled(context)) return
        // Callers must only provide fixed event labels, enum names, or numeric
        // values. Never pass a stream URL, title, exception message, or header.
        val report = load(context) ?: return
        val events = report.optJSONArray("events") ?: JSONArray()
        if (events.length() >= MAX_EVENTS) return
        val entry = JSONObject()
            .put("at_ms", (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0L))
            .put("name", name.take(40))
        if (detail != null) entry.put("detail", detail.take(60))
        if (value != null) entry.put("value", value)
        events.put(entry)
        report.put("events", events)
        save(context, report)
    }

    fun read(context: Context): Map<String, Any?>? {
        if (!enabled(context)) return null
        val report = load(context) ?: return null
        val events = report.optJSONArray("events") ?: JSONArray()
        return mapOf(
            "report_id" to report.optString("report_id"),
            "live" to report.optBoolean("live"),
            "mode" to report.optString("mode"),
            "events" to (0 until events.length()).mapNotNull { index ->
                events.optJSONObject(index)?.let { entry ->
                    mapOf(
                        "at_ms" to entry.optLong("at_ms"),
                        "name" to entry.optString("name"),
                        "detail" to entry.optString("detail"),
                        "value" to entry.optInt("value"),
                    )
                }
            },
        )
    }

    private fun load(context: Context): JSONObject? = runCatching {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(REPORT, null)?.let(::JSONObject)
    }.getOrNull()

    private fun save(context: Context, report: JSONObject) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(REPORT, report.toString()).apply()
    }
}
