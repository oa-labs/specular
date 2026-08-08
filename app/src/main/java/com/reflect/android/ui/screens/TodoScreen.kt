package com.specular.android.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import androidx.paging.compose.collectAsLazyPagingItems
import com.specular.android.domain.model.TodoFilter
import com.specular.android.ui.navigation.Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodoScreen(navController: NavController, vm: TodoViewModel = hiltViewModel()) {
    val filter by vm.filter.collectAsState()
    val indexReady by vm.indexReady.collectAsState()
    val pendingCompletion by vm.pendingCompletion.collectAsState()
    val todos = vm.todos.collectAsLazyPagingItems()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Todos") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        if (!indexReady) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) { CircularProgressIndicator() }
        } else {
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                TodoFilterControl(filter = filter, onSelect = vm::setFilter)
                if (todos.itemCount == 0) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = if (filter == TodoFilter.OPEN) "No open todos" else "No todos",
                            style = MaterialTheme.typography.bodyLarge
                        )
                    }
                } else {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(
                            count = todos.itemCount,
                            key = { index ->
                                todos.peek(index)?.let { "${it.noteId}:${it.taskIndex}" } ?: index
                            }
                        ) { index ->
                            val todo = todos[index] ?: return@items
                            val pendingState = pendingCompletion[todo.key()]
                            ListItem(
                                headlineContent = {
                                    if (todo.text.isBlank()) {
                                        Text("Untitled task")
                                    } else {
                                        MarkdownText(
                                            markdown = todo.text,
                                            taskOffset = 0,
                                            onTaskClick = {},
                                            onLinkClick = { false },
                                            onBodyClick = {
                                                navController.navigate(Screen.Detail.routeFor(todo.noteId))
                                            }
                                        )
                                    }
                                },
                                supportingContent = { Text(todo.noteTitle) },
                                leadingContent = {
                                    Checkbox(
                                        checked = pendingState ?: todo.isCompleted,
                                        onCheckedChange = { vm.toggle(todo) },
                                        enabled = pendingState == null
                                    )
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { navController.navigate(Screen.Detail.routeFor(todo.noteId)) }
                            )
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TodoFilterControl(filter: TodoFilter, onSelect: (TodoFilter) -> Unit) {
    val filters = TodoFilter.entries
    SingleChoiceSegmentedButtonRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        filters.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == filter,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = filters.size),
                label = { Text(option.name.lowercase().replaceFirstChar { it.uppercase() }) }
            )
        }
    }
}
