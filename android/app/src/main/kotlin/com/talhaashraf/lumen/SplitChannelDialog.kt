package com.talhaashraf.lumen

import android.app.Activity
import android.app.AlertDialog
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView

/** Local-only filtering and recycled rows: opening this browser starts no streams. */
internal object SplitChannelDialog {
    data class Channel(val index: Int, val title: String, val favorite: Boolean, val current: Boolean)

    fun show(
        activity: Activity,
        title: String,
        channels: List<Channel>,
        accent: Int,
        onPick: (Int) -> Unit,
        onDismiss: () -> Unit,
    ) {
        fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
        fun surface(color: Int, stroke: Int = Color.TRANSPARENT) = GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(12).toFloat()
            setStroke(dp(2), stroke)
        }
        fun text(value: String, size: Float, color: Int) = TextView(activity).apply {
            this.text = value
            textSize = size
            setTextColor(color)
        }
        val root = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(8))
        }
        root.addView(text(title, 22f, Color.WHITE))
        root.addView(text("Choose from this playlist · second screen starts muted", 13f, 0xFFADB4BD.toInt()).apply {
            setPadding(0, dp(6), 0, dp(14))
        })
        val search = EditText(activity).apply {
            hint = "Search channels"
            setSingleLine(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0xFFADB4BD.toInt())
            textSize = 16f
            setPadding(dp(14), 0, dp(14), 0)
            background = StateListDrawable().apply {
                addState(intArrayOf(android.R.attr.state_focused), surface(0xFF232930.toInt(), accent))
                addState(intArrayOf(), surface(0xFF232930.toInt()))
            }
        }
        root.addView(search, LinearLayout.LayoutParams(-1, dp(48)))
        val count = text("${channels.size} channels", 12f, 0xFFADB4BD.toInt()).apply {
            setPadding(0, dp(10), 0, dp(8))
        }
        root.addView(count)
        var visible = channels
        val list = ListView(activity).apply {
            divider = null
            dividerHeight = dp(6)
            setItemsCanFocus(false)
            selector = StateListDrawable().apply {
                addState(intArrayOf(android.R.attr.state_pressed), surface(0xFF303B29.toInt(), accent))
                addState(intArrayOf(android.R.attr.state_focused), surface(0xFF303B29.toInt(), accent))
                addState(intArrayOf(android.R.attr.state_selected), surface(0xFF303B29.toInt(), accent))
                addState(intArrayOf(), surface(Color.TRANSPARENT))
            }
        }
        val adapter = object : BaseAdapter() {
            override fun getCount() = visible.size
            override fun getItem(position: Int) = visible[position]
            override fun getItemId(position: Int) = visible[position].index.toLong()
            override fun hasStableIds() = true
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val row = convertView as? LinearLayout ?: LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    minimumHeight = dp(72)
                    setPadding(dp(14), dp(10), dp(14), dp(10))
                    addView(text("", 16f, accent).apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(dp(42), dp(42)))
                    addView(LinearLayout(activity).apply {
                        orientation = LinearLayout.VERTICAL
                        setPadding(dp(12), 0, dp(10), 0)
                        addView(text("", 16f, Color.WHITE).apply { maxLines = 2 })
                        addView(text("", 12f, 0xFFADB4BD.toInt()).apply { setPadding(0, dp(4), 0, 0) })
                    }, LinearLayout.LayoutParams(0, -2, 1f))
                    addView(text("", 22f, accent))
                }
                val channel = visible[position]
                (row.getChildAt(0) as TextView).apply {
                    text = (channel.index + 1).toString()
                    background = surface(0xFF29312A.toInt())
                }
                val labels = row.getChildAt(1) as LinearLayout
                (labels.getChildAt(0) as TextView).text = channel.title
                (labels.getChildAt(1) as TextView).text = when {
                    channel.current -> "ON THIS SCREEN"
                    channel.favorite -> "LIVE · MY LIST"
                    else -> "LIVE CHANNEL"
                }
                (row.getChildAt(2) as TextView).text = if (channel.current) "✓" else "+"
                return row
            }
        }
        list.adapter = adapter
        root.addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        val empty = text("No matching channels. Try another name.", 16f, Color.WHITE).apply {
            gravity = Gravity.CENTER
        }
        root.addView(empty, LinearLayout.LayoutParams(-1, 0, 1f))
        list.emptyView = empty
        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, countBefore: Int) {
                val query = s?.toString()?.trim().orEmpty()
                visible = channels.filter { it.title.contains(query, ignoreCase = true) }
                count.text = "${visible.size} of ${channels.size} channels"
                adapter.notifyDataSetChanged()
                list.setSelection(0)
            }
            override fun afterTextChanged(s: Editable?) {}
        })
        val dialog = AlertDialog.Builder(activity)
            .setView(root)
            .setNegativeButton("Close", null)
            .create()
        list.setOnItemClickListener { _, _, position, _ ->
            val channel = visible[position]
            dialog.dismiss()
            if (!channel.current) onPick(channel.index)
        }
        dialog.setOnDismissListener { onDismiss() }
        dialog.setOnShowListener {
            dialog.window?.apply {
                setBackgroundDrawable(surface(0xFF15181C.toInt()))
                setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN)
                val metrics = activity.resources.displayMetrics
                setLayout(minOf(dp(640), (metrics.widthPixels * .86f).toInt()), (metrics.heightPixels * .86f).toInt())
            }
            list.requestFocus()
            val current = visible.indexOfFirst { it.current }
            list.setSelection(current.coerceAtLeast(0))
        }
        dialog.show()
    }
}
