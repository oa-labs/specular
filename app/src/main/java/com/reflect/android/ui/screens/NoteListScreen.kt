package com.specular.android.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.specular.android.ui.navigation.Screen
import com.specular.android.ui.screens.NoteListViewModel


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteListScreen(navController: NavController, vm: NoteListViewModel = hiltViewModel()) {
    val notes by vm.notes.collectAsState()
    val sort by vm.sort.collectAsState()
    val folders by vm.folders.collectAsState()
    val deselectedFolders by vm.deselectedFolders.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val savedStateHandle = navController.currentBackStackEntry?.savedStateHandle
    var overflowExpanded by remember { mutableStateOf(false) }
    var sortExpanded by remember { mutableStateOf(false) }

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
                title = { Text("Specular") },
                actions = {
                    IconButton(onClick = { navController.navigate(Screen.Todos.route) }) {
                        Icon(Icons.Default.Checklist, "View todos")
                    }
                    IconButton(onClick = { navController.navigate(Screen.Search.route) }) { Icon(Icons.Default.Search, "Search") }
                    Box {
                        IconButton(onClick = { sortExpanded = true }) {
                            Icon(Icons.AutoMirrored.Filled.Sort, "Sort notes")
                        }
                        DropdownMenu(
                            expanded = sortExpanded,
                            onDismissRequest = { sortExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Last updated") },
                                onClick = {
                                    vm.setSort(NoteSort.LAST_UPDATED)
                                    sortExpanded = false
                                },
                                trailingIcon = {
                                    if (sort == NoteSort.LAST_UPDATED) {
                                        Icon(Icons.Default.Check, contentDescription = null)
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Alphabetical") },
                                onClick = {
                                    vm.setSort(NoteSort.ALPHABETICAL)
                                    sortExpanded = false
                                },
                                trailingIcon = {
                                    if (sort == NoteSort.ALPHABETICAL) {
                                        Icon(Icons.Default.Check, contentDescription = null)
                                    }
                                }
                            )
                        }
                    }
                    Box {
                        IconButton(onClick = { overflowExpanded = true }) {
                            Icon(Icons.Default.MoreVert, "More actions")
                        }
                        DropdownMenu(
                            expanded = overflowExpanded,
                            onDismissRequest = { overflowExpanded = false }
                        ) {
                            if (folders.isNotEmpty()) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(start = 16.dp, top = 8.dp, end = 12.dp, bottom = 4.dp),
                                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                                ) {
                                    Icon(Icons.Default.FilterList, contentDescription = null)
                                    Spacer(Modifier.width(12.dp))
                                    Text("Filter folders", style = MaterialTheme.typography.labelLarge)
                                }
                                folders.forEach { folder ->
                                    DropdownMenuItem(
                                        text = { Text(folder) },
                                        onClick = { vm.toggleFolder(folder) },
                                        trailingIcon = {
                                            Checkbox(
                                                checked = folder !in deselectedFolders,
                                                onCheckedChange = null
                                            )
                                        }
                                    )
                                }
                                HorizontalDivider()
                            }
                            DropdownMenuItem(
                                text = { Text("Settings") },
                                onClick = {
                                    overflowExpanded = false
                                    navController.navigate(Screen.Settings.route)
                                },
                                leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null) }
                            )
                        }
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { navController.navigate(Screen.Editor.routeForNew()) }) {
                Icon(Icons.Default.Add, "New note")
            }
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            if (notes.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize().weight(1f), contentAlignment = androidx.compose.ui.Alignment.Center) {
                    Column(
                        modifier = Modifier.padding(horizontal = 24.dp),
                        horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally
                    ) {
                        Text(
                            if (folders.isEmpty()) "No notes yet" else "No notes in selected folders",
                            style = MaterialTheme.typography.headlineSmall
                        )
                        Text(
                            if (folders.isEmpty()) {
                                "Notes sync automatically in the background once GitHub is configured. Tap + to create one."
                            } else {
                                "Open the menu to select one or more folders."
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                }
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize().weight(1f)) {
                    items(notes, key = { it.id }) { item ->
                        ListItem(
                            headlineContent = { Text(item.title) },
                            supportingContent = {
                                if (!item.snippet.isNullOrBlank()) Text(item.snippet, maxLines = 2)
                            },
                            trailingContent = {
                                Row {
                                    if (item.isDirty) Badge { Text("•") }
                                    if (item.isConflict) Badge(containerColor = MaterialTheme.colorScheme.error) { Text("!") }
                                    noteFolderLabel(item)?.let { label ->
                                        Text(" $label", style = MaterialTheme.typography.labelSmall)
                                    }
                                }
                            },
                            modifier = Modifier.clickable { navController.navigate(Screen.Detail.routeFor(item.id)) }
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}

internal fun noteFolderLabel(item: com.specular.android.domain.model.NoteListItem): String? =
    item.path.substringBefore('/', missingDelimiterValue = "")
        .takeIf { it.isNotBlank() && !it.equals("assets", ignoreCase = true) && !it.equals("attachments", ignoreCase = true) }

internal const val DELETED_NOTE_ID = "deleted_note_id"
internal const val DELETED_NOTE_TITLE = "deleted_note_title"
