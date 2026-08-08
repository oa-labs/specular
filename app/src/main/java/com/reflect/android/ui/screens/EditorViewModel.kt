package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.net.Uri
import com.specular.android.data.repo.AttachmentRepository
import com.specular.android.data.repo.NoteRepository
import com.specular.android.domain.model.NoteListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.util.Locale
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
    private val _selectedFolder = MutableStateFlow<String?>(null)
    val selectedFolder: StateFlow<String?> = _selectedFolder
    private var editingId: String? = null
    private var editingPath: String? = null

    val linkSuggestions: StateFlow<List<String>> = repo.observeNotes()
        .map { notes -> notes.map { it.title }.distinct().sorted() }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val availableFolders: StateFlow<List<String>> = repo.observeNotes()
        .map(::creationFolders)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Starts a regular note; a folder can be selected before saving. */
    fun prepareNewNote() {
        editingId = null
        editingPath = null
        _title.value = ""
        _body.value = ""
        _selectedFolder.value = null
    }

    fun load(id: String) {
        editingId = id
        viewModelScope.launch {
            val note = repo.getNote(id) ?: return@launch
            _title.value = note.title
            // The title has its own field. Do not make an existing H1 look like body
            // content or preserve an old title when the note is renamed.
            _body.value = note.bodyMarkdown.replaceFirst(
                Regex("""^\s*#\s+[^\r\n]+(?:\r?\n){0,2}"""),
                ""
            )
            editingPath = note.path
        }
    }

    fun setTitle(v: String) { _title.value = v }
    fun setBody(v: String) { _body.value = v }
    fun setFolder(folder: String?) { _selectedFolder.value = folder }

    fun insertMarkdown(prefix: String, suffix: String = "") {
        _body.value = _body.value.trimEnd() + "\n" + prefix + suffix
    }

    fun insertWikiLink(title: String) {
        val openingLink = Regex("""\[\[[^\]\n]*$""")
        _body.value = if (openingLink.containsMatchIn(_body.value)) {
            _body.value.replace(openingLink, "[[$title]]")
        } else {
            _body.value.trimEnd() + "\n[[$title]]"
        }
    }

    /** Starts an editor that immediately contains one open Markdown task. */
    fun prepareNewTodo() {
        editingId = null
        editingPath = null
        _title.value = "New to-do"
        _body.value = "- [ ] "
        _selectedFolder.value = null
    }

    fun importImage(uri: Uri) {
        viewModelScope.launch {
            try {
                val newNotePath = _selectedFolder.value?.let { "$it/untitled.md" } ?: "untitled.md"
                val reference = attachments.importImage(uri, editingPath ?: newNotePath)
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
                    repo.createNote(_title.value.ifBlank { "Untitled" }, _body.value, _selectedFolder.value).id
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

/** Folders that users can select when creating regular notes. */
internal fun creationFolders(notes: List<NoteListItem>): List<String> =
    notes.mapNotNull { note ->
        note.path.substringBefore('/', missingDelimiterValue = "")
            .takeIf { folder ->
                folder.isNotBlank() &&
                    !folder.equals("daily", ignoreCase = true) &&
                    !folder.equals("assets", ignoreCase = true) &&
                    !folder.equals("attachments", ignoreCase = true)
            }
    }
        .distinctBy { it.lowercase(Locale.ROOT) }
        .sortedWith(String.CASE_INSENSITIVE_ORDER)
