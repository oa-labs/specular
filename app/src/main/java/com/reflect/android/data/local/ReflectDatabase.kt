package com.specular.android.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [NoteEntity::class, NoteFts::class, TodoEntity::class, TodoIndexState::class, AttachmentEntity::class],
    version = 6,
    exportSchema = false
)
abstract class SpecularDatabase : RoomDatabase() {
    abstract fun noteDao(): NoteDao
    abstract fun attachmentDao(): AttachmentDao

    companion object {
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE notes ADD COLUMN snippet TEXT")
            }
        }

        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE notes ADD COLUMN isPendingDeletion INTEGER NOT NULL DEFAULT 0"
                )
            }
        }

        val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS todo_index (" +
                        "noteId TEXT NOT NULL, taskIndex INTEGER NOT NULL, text TEXT NOT NULL, " +
                        "isCompleted INTEGER NOT NULL, PRIMARY KEY(noteId, taskIndex))"
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS index_todo_index_isCompleted_noteId " +
                        "ON todo_index (isCompleted, noteId)"
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS todo_index_state (" +
                        "id INTEGER NOT NULL, isReady INTEGER NOT NULL, PRIMARY KEY(id))"
                )
                db.execSQL("INSERT OR REPLACE INTO todo_index_state (id, isReady) VALUES (0, 0)")
            }
        }

        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE notes ADD COLUMN pendingRenameFromPath TEXT")
                db.execSQL("ALTER TABLE notes ADD COLUMN pendingRenameFromSha TEXT")
            }
        }

        val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS attachments (" +
                        "path TEXT NOT NULL, mimeType TEXT, lastRemoteSha TEXT, " +
                        "isDirty INTEGER NOT NULL, updatedAt INTEGER NOT NULL, PRIMARY KEY(path))"
                )
            }
        }

    }
}
