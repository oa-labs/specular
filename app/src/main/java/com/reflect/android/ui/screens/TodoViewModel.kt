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
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.launch
import javax.inject.Inject

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@HiltViewModel
class TodoViewModel @Inject constructor(private val repo: NoteRepository) : ViewModel() {
    private val _filter = MutableStateFlow(TodoFilter.OPEN)
    val filter: StateFlow<TodoFilter> = _filter

    private val _indexReady = MutableStateFlow(false)
    val indexReady: StateFlow<Boolean> = _indexReady

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
        viewModelScope.launch { repo.toggleTodo(todo.noteId, todo.taskIndex) }
    }
}
