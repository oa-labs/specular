package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.repo.NoteRepository
import com.specular.android.domain.model.NoteListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SearchViewModel @Inject constructor(private val repo: NoteRepository) : ViewModel() {
    private val _results = MutableStateFlow<List<NoteListItem>>(emptyList())
    val results: StateFlow<List<NoteListItem>> = _results
    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching
    private var searchJob: Job? = null

    fun search(q: String) {
        searchJob?.cancel()
        if (q.isBlank()) {
            _results.value = emptyList()
            _isSearching.value = false
            return
        }
        _results.value = emptyList()
        searchJob = viewModelScope.launch {
            _isSearching.value = true
            // Let a short burst of typing settle before hitting the database, and
            // cancel the old flow so results can never belong to a previous query.
            delay(200)
            repo.search(q).collect {
                _results.value = it
                _isSearching.value = false
            }
        }
    }

    fun undoDelete(id: String) {
        viewModelScope.launch { repo.undoDeleteNote(id) }
    }
}
