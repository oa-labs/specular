package com.specular.android.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent

/** Native Android surface backed by the same reflect.db used by Flutter. */
class TodoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        TodoWidgetRenderer.requestUpdate(context, ids)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_COMPLETE -> {
                val noteId = intent.getStringExtra(EXTRA_NOTE_ID) ?: return
                val taskIndex = intent.getIntExtra(EXTRA_TASK_INDEX, -1)
                if (taskIndex < 0) return
                val pending = goAsync()
                Thread {
                    try {
                        TodoWidgetStore(context).toggle(noteId, taskIndex)
                        TodoWidgetRenderer.update(context)
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
            ACTION_OPEN_NOTE, ACTION_OPEN_TODOS, ACTION_NEW_TODO -> openApp(context, intent)
        }
    }

    private fun openApp(context: Context, source: Intent) {
        context.startActivity(Intent(context, com.specular.android.MainActivity::class.java).apply {
            action = source.action
            putExtras(source)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        })
    }

    companion object {
        const val ACTION_COMPLETE = "com.specular.android.widget.COMPLETE"
        const val ACTION_OPEN_NOTE = "com.specular.android.widget.OPEN_NOTE"
        const val ACTION_OPEN_TODOS = "com.specular.android.widget.OPEN_TODOS"
        const val ACTION_NEW_TODO = "com.specular.android.widget.NEW_TODO"
        const val EXTRA_NOTE_ID = "note_id"
        const val EXTRA_TASK_INDEX = "task_index"
    }
}
