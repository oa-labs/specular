package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.*
import com.specular.android.data.repo.NoteRepository
import com.specular.android.data.remote.AiProviderSettings
import com.specular.android.domain.model.NoteListItem
import com.specular.android.sync.SyncWorker
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.CancellationException
import androidx.work.WorkManager
import java.util.Locale
import javax.inject.Inject

enum class NoteSort {
    LAST_UPDATED,
    ALPHABETICAL
}

internal fun sortNotes(notes: List<NoteListItem>, sort: NoteSort): List<NoteListItem> = when (sort) {
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

@HiltViewModel
class NoteListViewModel @Inject constructor(
    private val repo: NoteRepository,
    private val workManager: WorkManager,
    private val aiSettings: AiProviderSettings
) : ViewModel() {
    private val _sort = MutableStateFlow(NoteSort.LAST_UPDATED)
    val sort: StateFlow<NoteSort> = _sort

    val notes: StateFlow<List<NoteListItem>> = combine(repo.observeNotes(), _sort) { notes, sort ->
        sortNotes(notes, sort)
    }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing

    private val _syncMessage = MutableStateFlow<String?>(null)
    val syncMessage: StateFlow<String?> = _syncMessage

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

    fun sync() {
        _isSyncing.value = true
        _syncMessage.value = null
        val req = OneTimeWorkRequestBuilder<SyncWorker>().build()
        workManager.enqueue(req)

        viewModelScope.launch {
            workManager.getWorkInfoByIdFlow(req.id).collect { info ->
                if (info?.state?.isFinished == true) {
                    _isSyncing.value = false
                    _syncMessage.value = if (info.state == WorkInfo.State.FAILED) {
                        info.outputData.getString(SyncWorker.ERROR_MESSAGE)
                            ?: "Sync failed. Please check your GitHub settings and try again."
                    } else {
                        null
                    }
                }
            }
        }
    }

    fun setSort(sort: NoteSort) {
        _sort.value = sort
    }
}
