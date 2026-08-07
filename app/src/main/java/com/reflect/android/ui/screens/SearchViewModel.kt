package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.repo.NoteRepository
import com.specular.android.domain.model.NoteListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SearchViewModel @Inject constructor(private val repo: NoteRepository) : ViewModel() {
    private val _results = MutableStateFlow<List<NoteListItem>>(emptyList())
    val results: StateFlow<List<NoteListItem>> = _results

    fun search(q: String) {
        viewModelScope.launch {
            repo.search(q).collect { _results.value = it }
        }
    }

    fun undoDelete(id: String) {
        viewModelScope.launch { repo.undoDeleteNote(id) }
    }
}
