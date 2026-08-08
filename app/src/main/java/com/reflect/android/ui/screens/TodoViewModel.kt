package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.specular.android.data.repo.NoteRepository
import com.specular.android.domain.model.TodoFilter
import com.specular.android.domain.model.TodoListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@HiltViewModel
class TodoViewModel @Inject constructor(private val repo: NoteRepository) : ViewModel() {
    private val _filter = MutableStateFlow(TodoFilter.OPEN)
    val filter: StateFlow<TodoFilter> = _filter

    private val _indexReady = MutableStateFlow(false)
    val indexReady: StateFlow<Boolean> = _indexReady

    /** The intended completion state while the local note update is in flight. */
    private val _pendingCompletion = MutableStateFlow<Map<String, Boolean>>(emptyMap())
    val pendingCompletion: StateFlow<Map<String, Boolean>> = _pendingCompletion.asStateFlow()

    val todos: StateFlow<PagingData<TodoListItem>> = _filter
        .flatMapLatest(repo::observeTodos)
        .cachedIn(viewModelScope)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PagingData.empty())

    init {
        viewModelScope.launch {
            repo.ensureTodoIndex()
            _indexReady.value = true
        }
    }

    fun setFilter(filter: TodoFilter) {
        _filter.value = filter
    }

    fun toggle(todo: TodoListItem) {
        val key = todo.key()
        if (_pendingCompletion.value.containsKey(key)) return

        _pendingCompletion.update { it + (key to !todo.isCompleted) }
        viewModelScope.launch {
            try {
                // Yield the main thread before the file/database work so the checked
                // state is drawn immediately.
                withContext(Dispatchers.IO) { repo.toggleTodo(todo.noteId, todo.taskIndex) }
            } finally {
                _pendingCompletion.update { it - key }
            }
        }
    }
}

internal fun TodoListItem.key(): String = "$noteId:$taskIndex"
