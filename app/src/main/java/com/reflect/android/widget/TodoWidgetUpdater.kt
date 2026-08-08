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

        val todos = noteStoreLock.withLock {
            // A widget may be the first task-related surface opened after an upgrade.
            // Build the derived index here instead of presenting a misleading empty list.
            if (dao.todoIndexReady() != true) {
                val indexed = dao.getAllForTodoIndex().flatMap { todoIndex.extract(it.id, it.body) }
                dao.replaceAllTodos(indexed)
            }
            dao.getOpenTodosForWidget(MAX_TODOS)
        }
        ids.forEach { id -> manager.updateAppWidget(id, buildViews(todos)) }
    }

    private fun buildViews(todos: List<TodoListItem>): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_todo).apply {
            removeAllViews(R.id.todo_widget_rows)
            if (todos.isEmpty()) {
                setViewVisibility(R.id.todo_widget_empty, android.view.View.VISIBLE)
            } else {
                setViewVisibility(R.id.todo_widget_empty, android.view.View.GONE)
                todos.forEach { todo ->
                    addView(R.id.todo_widget_rows, buildTodoRow(todo))
                }
            }
            setOnClickPendingIntent(R.id.todo_widget_add, newTodoPendingIntent())
            setOnClickPendingIntent(R.id.todo_widget_header, openTodosPendingIntent())
        }

    private fun buildTodoRow(todo: TodoListItem): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_todo_row).apply {
            setTextViewText(R.id.todo_widget_text, todo.text.ifBlank { context.getString(R.string.untitled_task) })
            setTextViewText(R.id.todo_widget_note, todo.noteTitle)
            setImageViewResource(R.id.todo_widget_complete, R.drawable.ic_widget_check_circle)
            setOnClickPendingIntent(R.id.todo_widget_complete, completePendingIntent(todo))
            setOnClickPendingIntent(R.id.todo_widget_row, openNotePendingIntent(todo.noteId))
        }

    private fun completePendingIntent(todo: TodoListItem): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, TodoWidgetProvider::class.java).apply {
                action = TodoWidgetProvider.ACTION_COMPLETE_TODO
                data = android.net.Uri.parse("specular://widget/complete/${todo.noteId}/${todo.taskIndex}")
                putExtra(TodoWidgetProvider.EXTRA_NOTE_ID, todo.noteId)
                putExtra(TodoWidgetProvider.EXTRA_TASK_INDEX, todo.taskIndex)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun openNotePendingIntent(noteId: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                action = TodoWidgetProvider.ACTION_OPEN_NOTE
                data = android.net.Uri.parse("specular://widget/note/$noteId")
                putExtra(TodoWidgetProvider.EXTRA_NOTE_ID, noteId)
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
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
        const val MAX_TODOS = 6
    }
}
