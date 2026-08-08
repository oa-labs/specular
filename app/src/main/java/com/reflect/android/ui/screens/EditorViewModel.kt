package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.net.Uri
import com.specular.android.data.repo.AttachmentRepository
import com.specular.android.data.repo.NoteRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class EditorViewModel @Inject constructor(
    private val repo: NoteRepository,
    private val attachments: AttachmentRepository
) : ViewModel() {
    private val _title = MutableStateFlow("")
    val title: StateFlow<String> = _title
    private val _body = MutableStateFlow("")
    val body: StateFlow<String> = _body
    private val _saving = MutableStateFlow(false)
    val saving: StateFlow<Boolean> = _saving
    private var editingId: String? = null
    private var editingPath: String? = null

    fun load(id: String) {
        editingId = id
        viewModelScope.launch {
            val note = repo.getNote(id) ?: return@launch
            _title.value = note.title
            _body.value = note.bodyMarkdown
            editingPath = note.path
        }
    }

    fun setTitle(v: String) { _title.value = v }
    fun setBody(v: String) { _body.value = v }

    /** Starts an editor that immediately contains one open Markdown task. */
    fun prepareNewTodo() {
        editingId = null
        editingPath = null
        _title.value = "New to-do"
        _body.value = "- [ ] "
    }

    fun importImage(uri: Uri) {
        viewModelScope.launch {
            try {
                // New notes are created at repository root, so this fallback produces
                // the same relative attachment reference as their eventual path.
                val reference = attachments.importImage(uri, editingPath ?: "untitled.md")
                _body.value += "\n![]($reference)\n"
            } catch (_: Exception) {
                // The editor remains usable if a provider revokes a picked URI.
            }
        }
    }

    fun save(isNew: Boolean, onDone: (String) -> Unit) {
        viewModelScope.launch {
            _saving.value = true
            try {
                val id = if (isNew) {
                    repo.createNote(_title.value.ifBlank { "Untitled" }, _body.value).id
                } else {
                    repo.updateNote(editingId!!, newTitle = _title.value, newBody = _body.value).id
                }
                editingPath = repo.getNote(id)?.path
                try {
                    repo.generateSnippet(id, force = true)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // The edit is already saved; snippet generation can be retried later.
                }
                onDone(id)
            } finally { _saving.value = false }
        }
    }
}
