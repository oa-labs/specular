package com.specular.android.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.specular.android.R

object TodoWidgetRenderer {
    fun requestUpdate(context: Context, ids: IntArray? = null) {
        Thread { update(context, ids) }.start()
    }

    fun update(context: Context, requestedIds: IntArray? = null) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = requestedIds ?: manager.getAppWidgetIds(ComponentName(context, TodoWidgetProvider::class.java))
        if (ids.isEmpty()) return
        ids.forEach { id -> manager.updateAppWidget(id, views(context, id)) }
        manager.notifyAppWidgetViewDataChanged(ids, R.id.todo_widget_list)
    }

    private fun views(context: Context, id: Int) = RemoteViews(context.packageName, R.layout.widget_todo).apply {
        setRemoteAdapter(R.id.todo_widget_list, Intent(context, TodoWidgetService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            data = Uri.parse("specular://widget/list/$id")
        })
        setEmptyView(R.id.todo_widget_list, R.id.todo_widget_empty)
        setPendingIntentTemplate(R.id.todo_widget_list, broadcast(context, id))
        setOnClickPendingIntent(R.id.todo_widget_header, activity(context, TodoWidgetProvider.ACTION_OPEN_TODOS, id))
        setOnClickPendingIntent(R.id.todo_widget_add, activity(context, TodoWidgetProvider.ACTION_NEW_TODO, id))
    }

    fun rowIntent(interaction: String, todo: WidgetTodo): Intent = Intent().apply {
        putExtra(TodoWidgetProvider.EXTRA_INTERACTION, interaction)
        putExtra(TodoWidgetProvider.EXTRA_NOTE_ID, todo.noteId)
        putExtra(TodoWidgetProvider.EXTRA_TASK_INDEX, todo.taskIndex)
    }

    private fun broadcast(context: Context, id: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            id,
            Intent(context, TodoWidgetProvider::class.java).apply {
                action = TodoWidgetProvider.ACTION_TODO_INTERACTION
                data = Uri.parse("specular://widget/interaction/$id")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )

    private fun activity(context: Context, action: String, id: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            id + action.hashCode(),
            Intent(context, TodoWidgetProvider::class.java).apply {
                this.action = action
                data = Uri.parse("specular://widget/action/$id/$action")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
