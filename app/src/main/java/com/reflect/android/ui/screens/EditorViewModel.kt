package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.repo.NoteRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class EditorViewModel @Inject constructor(private val repo: NoteRepository) : ViewModel() {
    private val _title = MutableStateFlow("")
    val title: StateFlow<String> = _title
    private val _body = MutableStateFlow("")
    val body: StateFlow<String> = _body
    private val _saving = MutableStateFlow(false)
    val saving: StateFlow<Boolean> = _saving
    private var editingId: String? = null

    fun load(id: String) {
        editingId = id
        viewModelScope.launch {
            val note = repo.getNote(id) ?: return@launch
            _title.value = note.title
            _body.value = note.bodyMarkdown
        }
    }

    fun setTitle(v: String) { _title.value = v }
    fun setBody(v: String) { _body.value = v }

    fun insertImage(markdownPath: String) {
        val tag = "\n![]($markdownPath)\n"
        _body.value = _body.value + tag
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
                onDone(id)
            } finally { _saving.value = false }
        }
    }
}
