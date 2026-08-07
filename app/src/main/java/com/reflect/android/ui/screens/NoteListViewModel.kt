package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.*
import com.specular.android.data.repo.NoteRepository
import com.specular.android.domain.model.NoteListItem
import com.specular.android.sync.SyncWorker
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import androidx.work.WorkManager
import javax.inject.Inject

@HiltViewModel
class NoteListViewModel @Inject constructor(
    private val repo: NoteRepository,
    private val workManager: WorkManager
) : ViewModel() {
    val notes: StateFlow<List<NoteListItem>> = repo.observeNotes()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing

    fun sync() {
        _isSyncing.value = true
        val req = OneTimeWorkRequestBuilder<SyncWorker>().build()
        workManager.enqueue(req)
        // observe work — simplified
        viewModelScope.launch {
            workManager.getWorkInfoByIdFlow(req.id).collect { info ->
                if (info?.state?.isFinished == true) _isSyncing.value = false
            }
        }
    }
}
