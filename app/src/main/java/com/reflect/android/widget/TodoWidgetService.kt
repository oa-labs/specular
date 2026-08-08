package com.specular.android.widget

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.specular.android.R
import com.specular.android.domain.model.TodoListItem
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking

/** Supplies scrollable task rows to every instance of the home-screen widget. */
class TodoWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TodoWidgetRemoteViewsFactory(applicationContext)
}

private class TodoWidgetRemoteViewsFactory(
    private val context: Context
) : RemoteViewsService.RemoteViewsFactory {
    private var todos: List<TodoListItem> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        todos = runBlocking(Dispatchers.IO) {
            EntryPointAccessors.fromApplication(context, TodoWidgetEntryPoint::class.java)
                .updater()
                .openTodos()
        }
    }

    override fun onDestroy() = Unit

    override fun getCount(): Int = todos.size

    override fun getViewAt(position: Int): RemoteViews? {
        val todo = todos.getOrNull(position) ?: return null
        return RemoteViews(context.packageName, R.layout.widget_todo_row).apply {
            setTextViewText(
                R.id.todo_widget_text,
                renderWidgetMarkdown(todo.text.ifBlank { context.getString(R.string.untitled_task) })
            )
            setTextViewText(R.id.todo_widget_note, todo.noteTitle)
            setImageViewResource(R.id.todo_widget_complete, R.drawable.ic_widget_open_circle)
            setOnClickFillInIntent(
                R.id.todo_widget_complete,
                interactionIntent(TodoWidgetProvider.INTERACTION_COMPLETE, todo)
            )
            val openIntent = interactionIntent(TodoWidgetProvider.INTERACTION_OPEN, todo)
            // RemoteViews does not reliably bubble clicks from nested text views to
            // the collection-row root on all launchers, so bind the visible body.
            setOnClickFillInIntent(R.id.todo_widget_row, openIntent)
            setOnClickFillInIntent(R.id.todo_widget_content, openIntent)
            setOnClickFillInIntent(R.id.todo_widget_text, openIntent)
            setOnClickFillInIntent(R.id.todo_widget_note, openIntent)
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        todos.getOrNull(position)?.let { "${it.noteId}:${it.taskIndex}".hashCode().toLong() } ?: position.toLong()

    override fun hasStableIds(): Boolean = true

    private fun interactionIntent(type: String, todo: TodoListItem): Intent = Intent().apply {
        putExtra(TodoWidgetProvider.EXTRA_INTERACTION, type)
        putExtra(TodoWidgetProvider.EXTRA_NOTE_ID, todo.noteId)
        putExtra(TodoWidgetProvider.EXTRA_TASK_INDEX, todo.taskIndex)
    }
}
