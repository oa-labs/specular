package com.specular.android.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Receives home-screen interactions and delegates mutations to the normal repository flow. */
class TodoWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        dependencies(context).updater().requestUpdate(appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != ACTION_COMPLETE_TODO) return

        val noteId = intent.getStringExtra(EXTRA_NOTE_ID) ?: return
        val taskIndex = intent.getIntExtra(EXTRA_TASK_INDEX, NO_TASK_INDEX)
        if (taskIndex == NO_TASK_INDEX) return

        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val entryPoint = dependencies(context)
                entryPoint.repository().toggleTodo(noteId, taskIndex)
                entryPoint.updater().update()
            } finally {
                pendingResult.finish()
            }
        }
    }

    private fun dependencies(context: Context): TodoWidgetEntryPoint =
        EntryPointAccessors.fromApplication(context.applicationContext, TodoWidgetEntryPoint::class.java)

    companion object {
        const val ACTION_COMPLETE_TODO = "com.specular.android.widget.COMPLETE_TODO"
        const val ACTION_OPEN_NOTE = "com.specular.android.widget.OPEN_NOTE"
        const val ACTION_NEW_TODO = "com.specular.android.widget.NEW_TODO"
        const val ACTION_OPEN_TODOS = "com.specular.android.widget.OPEN_TODOS"
        const val EXTRA_NOTE_ID = "note_id"
        const val EXTRA_TASK_INDEX = "task_index"
        private const val NO_TASK_INDEX = -1
    }
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface TodoWidgetEntryPoint {
    fun repository(): com.specular.android.data.repo.NoteRepository
    fun updater(): TodoWidgetUpdater
}
