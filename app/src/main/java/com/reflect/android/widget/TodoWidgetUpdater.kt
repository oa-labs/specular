package com.specular.android.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.specular.android.R
import com.specular.android.data.local.NoteDao
import com.specular.android.data.local.NoteStoreLock
import com.specular.android.data.local.TodoIndex
import com.specular.android.domain.model.TodoListItem
import com.specular.android.ui.MainActivity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/** Renders every active widget from the local todo index. */
@Singleton
class TodoWidgetUpdater @Inject constructor(
    @ApplicationContext private val context: Context,
    private val dao: NoteDao,
    private val noteStoreLock: NoteStoreLock,
    private val todoIndex: TodoIndex
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun requestUpdate(appWidgetIds: IntArray? = null) {
        scope.launch {
            runCatching { update(appWidgetIds) }
        }
    }

    suspend fun update(appWidgetIds: IntArray? = null) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = appWidgetIds ?: manager.getAppWidgetIds(
            ComponentName(context, TodoWidgetProvider::class.java)
        )
        if (ids.isEmpty()) return

        // Populate the derived index before the collection service is asked for rows.
        openTodos()
        ids.forEach { id -> manager.updateAppWidget(id, buildViews(id)) }
        manager.notifyAppWidgetViewDataChanged(ids, R.id.todo_widget_list)
    }

    suspend fun openTodos(): List<TodoListItem> = noteStoreLock.withLock {
            // A widget may be the first task-related surface opened after an upgrade.
            // Build the derived index here instead of presenting a misleading empty list.
            if (dao.todoIndexReady() != true) {
                val indexed = dao.getAllForTodoIndex().flatMap { todoIndex.extract(it.id, it.body) }
                dao.replaceAllTodos(indexed)
            }
            dao.getOpenTodosForWidget(MAX_TODOS)
        }

    private fun buildViews(appWidgetId: Int): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_todo).apply {
            setRemoteAdapter(R.id.todo_widget_list, Intent(context, TodoWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                // Adapter intents with otherwise identical extras are treated as the same.
                data = android.net.Uri.parse("specular://widget/list/$appWidgetId")
            })
            setEmptyView(R.id.todo_widget_list, R.id.todo_widget_empty)
            setPendingIntentTemplate(R.id.todo_widget_list, todoInteractionPendingIntent(appWidgetId))
            setOnClickPendingIntent(R.id.todo_widget_add, newTodoPendingIntent())
            setOnClickPendingIntent(R.id.todo_widget_header, openTodosPendingIntent())
        }

    private fun todoInteractionPendingIntent(appWidgetId: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, TodoWidgetProvider::class.java).apply {
                action = TodoWidgetProvider.ACTION_TODO_INTERACTION
                data = android.net.Uri.parse("specular://widget/interaction/$appWidgetId")
            },
            // Collection rows supply their note/task via fill-in intents. Android drops
            // that data for immutable pending intents, which makes every row inert.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

    private fun newTodoPendingIntent(): PendingIntent = activityPendingIntent(TodoWidgetProvider.ACTION_NEW_TODO)

    private fun openTodosPendingIntent(): PendingIntent = activityPendingIntent(TodoWidgetProvider.ACTION_OPEN_TODOS)

    private fun activityPendingIntent(action: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                this.action = action
                data = android.net.Uri.parse("specular://widget/$action")
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private companion object {
        const val MAX_TODOS = 200
    }
}
