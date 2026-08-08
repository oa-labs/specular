package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.repo.NoteRepository
import com.specular.android.data.remote.AiProviderSettings
import com.specular.android.domain.model.NoteListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
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

@HiltViewModel
class NoteListViewModel @Inject constructor(
    private val repo: NoteRepository,
    private val aiSettings: AiProviderSettings
) : ViewModel() {
    private val _sort = MutableStateFlow(NoteSort.LAST_UPDATED)
    val sort: StateFlow<NoteSort> = _sort

    val notes: StateFlow<List<NoteListItem>> = combine(repo.observeNotes(), _sort) { notes, sort ->
        sortNotes(notes, sort)
    }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val snippetJobs = mutableSetOf<String>()

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
}
