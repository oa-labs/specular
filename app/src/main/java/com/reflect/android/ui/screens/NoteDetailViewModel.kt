package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.repo.NoteRepository
import com.specular.android.domain.model.Note
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class NoteDetailViewModel @Inject constructor(private val repo: NoteRepository) : ViewModel() {
    data class DeletedNote(val id: String, val title: String)

    private val _note = MutableStateFlow<Note?>(null)
    val note: StateFlow<Note?> = _note
    private val _isRegenerating = MutableStateFlow(false)
    val isRegenerating: StateFlow<Boolean> = _isRegenerating
    private val _deletedNotes = MutableSharedFlow<DeletedNote>()
    val deletedNotes: SharedFlow<DeletedNote> = _deletedNotes
    private val _linkedNoteIds = MutableSharedFlow<String>()
    val linkedNoteIds: SharedFlow<String> = _linkedNoteIds
    private val _renameError = MutableStateFlow<String?>(null)
    val renameError: StateFlow<String?> = _renameError

    fun load(id: String) {
        viewModelScope.launch { _note.value = repo.getNote(id) }
    }

    fun regenerateSnippet(id: String) {
        if (_isRegenerating.value) return
        viewModelScope.launch {
            _isRegenerating.value = true
            try {
                repo.generateSnippet(id, force = true)
                _note.value = repo.getNote(id)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Saving the note and displaying the existing snippet remain unaffected if
                // the configured provider is unavailable.
            } finally {
                _isRegenerating.value = false
            }
        }
    }

    fun toggleTask(id: String, taskIndex: Int) {
        viewModelScope.launch {
            _note.value = repo.toggleTodo(id, taskIndex) ?: return@launch
        }
    }

    fun openLinkedNote(path: String) {
        viewModelScope.launch {
            repo.findNoteIdByPath(path)?.let { _linkedNoteIds.emit(it) }
        }
    }

    fun deleteNote(id: String) {
        viewModelScope.launch {
            val title = _note.value?.title ?: return@launch
            repo.deleteNote(id)
            _note.value = null
            _deletedNotes.emit(DeletedNote(id, title))
        }
    }

    fun renameNote(id: String, path: String, onRenamed: () -> Unit) {
        viewModelScope.launch {
            try {
                _note.value = repo.renameNote(id, path)
                _renameError.value = null
                onRenamed()
            } catch (e: IllegalArgumentException) {
                _renameError.value = e.message ?: "Unable to rename note"
            } catch (e: IllegalStateException) {
                _renameError.value = e.message ?: "Unable to rename note"
            }
        }
    }

    fun clearRenameError() {
        _renameError.value = null
    }
}
