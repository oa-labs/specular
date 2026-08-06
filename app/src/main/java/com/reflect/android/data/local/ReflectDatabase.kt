package com.reflect.android.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [NoteEntity::class, NoteFts::class],
    version = 1,
    exportSchema = false
)
abstract class SpecularDatabase : RoomDatabase() {
    abstract fun noteDao(): NoteDao
}
