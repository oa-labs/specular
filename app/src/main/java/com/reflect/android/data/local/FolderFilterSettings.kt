package com.specular.android.data.local

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/** Persists the folders hidden from the note-list filter. */
@Singleton
class FolderFilterSettings @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val preferences by lazy {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    }

    fun deselectedFolders(): Set<String> =
        preferences.getStringSet(KEY_DESELECTED_FOLDERS, emptySet()).orEmpty().toSet()

    fun saveDeselectedFolders(folders: Set<String>) {
        preferences.edit()
            .putStringSet(KEY_DESELECTED_FOLDERS, folders.toSet())
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "note_list_filters"
        const val KEY_DESELECTED_FOLDERS = "deselected_folders"
    }
}
