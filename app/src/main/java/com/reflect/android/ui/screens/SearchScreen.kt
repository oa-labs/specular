package com.specular.android.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.specular.android.ui.navigation.Screen
import kotlinx.coroutines.flow.collectLatest

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(navController: NavController, vm: SearchViewModel = hiltViewModel()) {
    var query by remember { mutableStateOf("") }
    val results by vm.results.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val savedStateHandle = navController.currentBackStackEntry?.savedStateHandle

    LaunchedEffect(savedStateHandle) {
        savedStateHandle ?: return@LaunchedEffect
        savedStateHandle.getStateFlow<String?>(DELETED_NOTE_ID, null).collect { id ->
            if (id == null) return@collect
            val title = savedStateHandle.get<String>(DELETED_NOTE_TITLE).orEmpty()
            savedStateHandle[DELETED_NOTE_ID] = null
            savedStateHandle[DELETED_NOTE_TITLE] = null
            if (snackbarHostState.showSnackbar(
                    message = if (title.isBlank()) "Note deleted" else "Deleted $title",
                    actionLabel = "Undo",
                    withDismissAction = true
                ) == SnackbarResult.ActionPerformed
            ) {
                vm.undoDelete(id)
            }
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it; vm.search(it) },
                        placeholder = { Text("Search notes…") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) { Icon(Icons.Default.ArrowBack, "Back") }
                }
            )
        }
    ) { padding ->
        LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
            items(results, key = { it.id }) { item ->
                ListItem(
                    headlineContent = { Text(item.title) },
                    supportingContent = {
                        if (!item.snippet.isNullOrBlank()) Text(item.snippet, maxLines = 2)
                    },
                    modifier = Modifier.clickable { navController.navigate(Screen.Detail.routeFor(item.id)) }
                )
                HorizontalDivider()
            }
            if (results.isEmpty() && query.isNotBlank()) {
                item { Box(modifier = Modifier.fillMaxWidth().padding(24.dp)) { Text("No matches for \"$query\"") } }
            }
        }
    }
}
