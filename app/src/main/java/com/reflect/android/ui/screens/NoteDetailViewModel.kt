package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.repo.NoteRepository
import com.specular.android.domain.model.Note
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject

@HiltViewModel
class NoteDetailViewModel @Inject constructor(private val repo: NoteRepository) : ViewModel() {
    private val _note = MutableStateFlow<Note?>(null)
    val note: StateFlow<Note?> = _note
    private val _isRegenerating = MutableStateFlow(false)
    val isRegenerating: StateFlow<Boolean> = _isRegenerating
    private val taskMutationMutex = Mutex()

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
            taskMutationMutex.withLock {
                val current = _note.value ?: repo.getNote(id) ?: return@withLock
                val updatedBody = toggleTaskAtIndex(current.bodyMarkdown, taskIndex)
                if (updatedBody == current.bodyMarkdown) return@withLock
                _note.value = repo.updateNote(id, newBody = updatedBody)
            }
        }
    }
}

private val taskMarkerPattern = Regex(
    """(?m)^[ \t]*(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\]"""
)

internal fun countTaskItems(markdown: String): Int = taskMarkerPattern.findAll(markdown).count()

private fun toggleTaskAtIndex(markdown: String, taskIndex: Int): String {
    val match = taskMarkerPattern.findAll(markdown).elementAtOrNull(taskIndex) ?: return markdown
    val stateOffset = match.range.first + match.value.indexOf('[') + 1
    val currentState = match.groupValues[1]
    val nextState = if (currentState == " ") "x" else " "
    return markdown.replaceRange(stateOffset, stateOffset + 1, nextState)
}
