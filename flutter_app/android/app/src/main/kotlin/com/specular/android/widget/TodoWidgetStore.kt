package com.specular.android.widget

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File

data class WidgetTodo(val noteId: String, val taskIndex: Int, val text: String, val noteTitle: String)

/** A deliberately small SQLite reader/writer: it preserves the Flutter schema and marks edits dirty for GitHub sync. */
class TodoWidgetStore(private val context: Context) {
    fun openTodos(): List<WidgetTodo> = withDatabase(SQLiteDatabase.OPEN_READONLY) { db ->
        db.rawQuery(
            "SELECT t.noteId, t.taskIndex, t.text, n.title FROM todo_index t JOIN notes n ON n.id = t.noteId " +
                "WHERE n.isPendingDeletion = 0 AND t.isCompleted = 0 ORDER BY n.updatedAt DESC, t.taskIndex ASC LIMIT 200",
            null,
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(WidgetTodo(cursor.getString(0), cursor.getInt(1), cursor.getString(2), cursor.getString(3)))
            }
        }
    }

    fun toggle(noteId: String, taskIndex: Int) = withDatabase(SQLiteDatabase.OPEN_READWRITE) { db ->
        db.beginTransaction()
        try {
            val row = db.rawQuery("SELECT path, rawMarkdown, body FROM notes WHERE id = ?", arrayOf(noteId)).use { cursor ->
                if (!cursor.moveToFirst()) return@withDatabase
                Triple(cursor.getString(0), cursor.getString(1), cursor.getString(2))
            }
            val matches = taskRegex.findAll(row.third).toList()
            val match = matches.getOrNull(taskIndex) ?: return@withDatabase
            val toggled = match.value.replaceFirst(Regex("\\[.\\]"), if (match.groupValues[1].equals("x", true)) "[ ]" else "[x]")
            val body = row.third.replaceRange(match.range, toggled)
            val raw = row.second.replaceFirst(row.third, body)
            db.update("notes", ContentValues().apply {
                put("rawMarkdown", raw)
                put("body", body)
                put("isDirty", 1)
                put("updatedAt", System.currentTimeMillis())
            }, "id = ?", arrayOf(noteId))
            // Flutter's schema migration normally adds this column before the
            // widget runs. The fallback keeps an upgraded-but-not-yet-opened
            // install safe as well.
            try {
                db.execSQL("UPDATE notes SET localRevision = localRevision + 1 WHERE id = ?", arrayOf(noteId))
            } catch (_: Exception) {
                db.execSQL("ALTER TABLE notes ADD COLUMN localRevision INTEGER NOT NULL DEFAULT 0")
                db.execSQL("UPDATE notes SET localRevision = localRevision + 1 WHERE id = ?", arrayOf(noteId))
            }
            db.delete("todo_index", "noteId = ?", arrayOf(noteId))
            taskRegex.findAll(body).forEachIndexed { index, task ->
                db.insert("todo_index", null, ContentValues().apply {
                    put("noteId", noteId)
                    put("taskIndex", index)
                    put("text", task.groupValues[2].trim())
                    put("isCompleted", task.groupValues[1].equals("x", true))
                })
            }
            writeMarkdown(row.first, raw)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun writeMarkdown(path: String, markdown: String) {
        val root = File(context.filesDir, "notes").canonicalFile
        val target = File(root, path).canonicalFile
        if (target.path.startsWith(root.path + File.separator)) {
            target.parentFile?.mkdirs()
            target.writeText(markdown)
        }
    }

    private fun <T> withDatabase(flags: Int, block: (SQLiteDatabase) -> T): T {
        val db = SQLiteDatabase.openDatabase(context.getDatabasePath("reflect.db").path, null, flags)
        return try { block(db) } finally { db.close() }
    }

    private companion object {
        // Only Reflect global `+` tasks appear in the widget's source index.
        val taskRegex = Regex("(?m)^\\s*\\+\\s+\\[([ xX])\\]\\s*(.*)$")
    }
}
