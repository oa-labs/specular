package com.specular.android.widget

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.specular.android.R

class TodoWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = TodoFactory(applicationContext)
}

private class TodoFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var todos: List<WidgetTodo> = emptyList()

    override fun onCreate() = Unit
    override fun onDataSetChanged() { todos = TodoWidgetStore(context).openTodos() }
    override fun onDestroy() = Unit
    override fun getCount() = todos.size
    override fun getViewTypeCount() = 1
    override fun hasStableIds() = true
    override fun getLoadingView(): RemoteViews? = null
    override fun getItemId(position: Int) = todos.getOrNull(position)?.let { "${it.noteId}:${it.taskIndex}".hashCode().toLong() } ?: position.toLong()

    override fun getViewAt(position: Int): RemoteViews? {
        val todo = todos.getOrNull(position) ?: return null
        return RemoteViews(context.packageName, R.layout.widget_todo_row).apply {
            setTextViewText(R.id.todo_widget_text, renderWidgetMarkdown(todo.text.ifBlank { "Untitled task" }))
            setTextViewText(R.id.todo_widget_note, todo.noteTitle)
            setOnClickFillInIntent(R.id.todo_widget_complete, TodoWidgetRenderer.rowIntent(context, TodoWidgetProvider.ACTION_COMPLETE, todo))
            val open = TodoWidgetRenderer.rowIntent(context, TodoWidgetProvider.ACTION_OPEN_NOTE, todo)
            setOnClickFillInIntent(R.id.todo_widget_row, open)
            setOnClickFillInIntent(R.id.todo_widget_content, open)
        }
    }
}
