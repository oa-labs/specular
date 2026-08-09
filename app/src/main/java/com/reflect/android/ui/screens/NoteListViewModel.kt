package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.local.FolderFilterSettings
import com.specular.android.data.repo.NoteRepository
import com.specular.android.data.remote.AiProviderSettings
import com.specular.android.sync.SyncEngine
import com.specular.android.domain.model.NoteListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.CancellationException
import java.util.Locale
import javax.inject.Inject

enum class NoteSort {
    LAST_UPDATED,
    ALPHABETICAL
}

internal fun sortNotes(notes: List<NoteListItem>, sort: NoteSort): List<NoteListItem> {
    val withinPinGroup = when (sort) {
        NoteSort.LAST_UPDATED -> notes.sortedWith(
        compareByDescending<NoteListItem> { it.updatedAt }
            .thenBy { it.title.lowercase(Locale.ROOT) }
            .thenBy { it.path }
    )
        NoteSort.ALPHABETICAL -> notes.sortedWith(
        compareBy<NoteListItem> { it.title.lowercase(Locale.ROOT) }
            .thenBy { it.path }
    )
    }
    return withinPinGroup.sortedByDescending { it.isPinned }
}

/** Folders that are shown as labels on the home screen, in display order. */
internal fun noteFolders(notes: List<NoteListItem>): List<String> =
    notes.mapNotNull(::noteFolderLabel)
        .distinct()
        .sortedWith(String.CASE_INSENSITIVE_ORDER)

/** Root-level notes remain visible because they do not have a folder label to filter by. */
internal fun filterNotesByFolders(
    notes: List<NoteListItem>,
    deselectedFolders: Set<String>
): List<NoteListItem> = notes.filter { note ->
    noteFolderLabel(note) !in deselectedFolders
}

@HiltViewModel
class NoteListViewModel @Inject constructor(
    private val repo: NoteRepository,
    private val aiSettings: AiProviderSettings,
    private val folderFilterSettings: FolderFilterSettings,
    private val syncEngine: SyncEngine
) : ViewModel() {
    private val _sort = MutableStateFlow(NoteSort.LAST_UPDATED)
    val sort: StateFlow<NoteSort> = _sort
    private val _deselectedFolders = MutableStateFlow(folderFilterSettings.deselectedFolders())
    val deselectedFolders: StateFlow<Set<String>> = _deselectedFolders

    private val allNotes: StateFlow<List<NoteListItem>> = repo.observeNotes()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val folders: StateFlow<List<String>> = allNotes
        .map(::noteFolders)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val notes: StateFlow<List<NoteListItem>> = combine(allNotes, _sort, _deselectedFolders) {
            notes,
            sort,
            deselectedFolders ->
        sortNotes(filterNotesByFolders(notes, deselectedFolders), sort)
    }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val snippetJobs = mutableSetOf<String>()
    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing
    private val _syncMessage = MutableStateFlow<String?>(null)
    val syncMessage: StateFlow<String?> = _syncMessage
    private val _isOpeningToday = MutableStateFlow(false)
    val isOpeningToday: StateFlow<Boolean> = _isOpeningToday

    init {
        viewModelScope.launch {
            combine(repo.observeNotes(), aiSettings.config) { notes, config -> notes to config }
                .collect { (notes, config) ->
                    if (config == null) return@collect
                    notes.filter { it.snippet.isNullOrBlank() }.forEach { note ->
                        if (snippetJobs.add(note.id)) {
                            launch {
                                try {
                                    repo.generateSnippet(note.id)
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (_: Exception) {
                                    // A malformed/legacy note or an unavailable provider must not
                                    // take down the note list. It remains eligible for a later retry.
                                } finally {
                                    snippetJobs.remove(note.id)
                                }
                            }
                        }
                    }
                }
        }
    }

    fun undoDelete(id: String) {
        viewModelScope.launch { repo.undoDeleteNote(id) }
    }

    fun setSort(sort: NoteSort) {
        _sort.value = sort
    }

    fun toggleFolder(folder: String) {
        val updatedFolders = _deselectedFolders.value.toMutableSet().apply {
            if (!add(folder)) remove(folder)
        }
        _deselectedFolders.value = updatedFolders
        folderFilterSettings.saveDeselectedFolders(updatedFolders)
    }

    fun showAllFolders() {
        _deselectedFolders.value = emptySet()
        folderFilterSettings.saveDeselectedFolders(emptySet())
    }

    fun refresh() {
        if (_isRefreshing.value) return
        viewModelScope.launch {
            _isRefreshing.value = true
            _syncMessage.value = when (val result = syncEngine.sync()) {
                SyncEngine.Result.Success -> "Notes are up to date"
                SyncEngine.Result.NotConfigured -> "Connect a GitHub repository in Settings to sync"
                is SyncEngine.Result.Error -> result.message
            }
            _isRefreshing.value = false
        }
    }

    fun consumeSyncMessage() {
        _syncMessage.value = null
    }

    fun openToday(onReady: (String) -> Unit) {
        if (_isOpeningToday.value) return
        viewModelScope.launch {
            _isOpeningToday.value = true
            try {
                onReady(repo.getOrCreateTodayNote().id)
            } finally {
                _isOpeningToday.value = false
            }
        }
    }
}
