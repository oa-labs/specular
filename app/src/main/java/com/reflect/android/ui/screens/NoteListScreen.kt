package com.specular.android.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
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


@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class)
@Composable
fun NoteListScreen(navController: NavController, vm: NoteListViewModel = hiltViewModel()) {
    val notes by vm.notes.collectAsState()
    val sort by vm.sort.collectAsState()
    val folders by vm.folders.collectAsState()
    val deselectedFolders by vm.deselectedFolders.collectAsState()
    val isRefreshing by vm.isRefreshing.collectAsState()
    val syncMessage by vm.syncMessage.collectAsState()
    val isOpeningToday by vm.isOpeningToday.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val savedStateHandle = navController.currentBackStackEntry?.savedStateHandle
    var overflowExpanded by remember { mutableStateOf(false) }
    var createExpanded by remember { mutableStateOf(false) }
    val pullRefreshState = rememberPullRefreshState(isRefreshing, vm::refresh)
    val openTodayEditor = {
        vm.openToday { noteId -> navController.navigate(Screen.Editor.routeFor(noteId)) }
    }

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
    LaunchedEffect(syncMessage) {
        syncMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            vm.consumeSyncMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("Specular") },
                actions = {
                    IconButton(onClick = vm::refresh, enabled = !isRefreshing) {
                        if (isRefreshing) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.Refresh, "Sync now")
                    }
                    IconButton(onClick = { navController.navigate(Screen.Todos.route) }) {
                        Icon(Icons.Default.Checklist, "View todos")
                    }
                    IconButton(onClick = { navController.navigate(Screen.Search.route) }) { Icon(Icons.Default.Search, "Search") }
                    Box {
                        IconButton(onClick = { overflowExpanded = true }) {
                            Icon(Icons.Default.MoreVert, "More actions")
                        }
                        DropdownMenu(
                            expanded = overflowExpanded,
                            onDismissRequest = { overflowExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Sort by last updated") },
                                onClick = {
                                    vm.setSort(NoteSort.LAST_UPDATED)
                                    overflowExpanded = false
                                },
                                trailingIcon = {
                                    if (sort == NoteSort.LAST_UPDATED) {
                                        Icon(Icons.Default.Check, contentDescription = null)
                                    }
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Sort alphabetically") },
                                onClick = {
                                    vm.setSort(NoteSort.ALPHABETICAL)
                                    overflowExpanded = false
                                },
                                trailingIcon = {
                                    if (sort == NoteSort.ALPHABETICAL) {
                                        Icon(Icons.Default.Check, contentDescription = null)
                                    }
                                }
                            )
                            HorizontalDivider()
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
            Column(
                horizontalAlignment = androidx.compose.ui.Alignment.End,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box {
                    SmallFloatingActionButton(onClick = { createExpanded = true }) {
                        Icon(Icons.Default.MoreVert, "More ways to add")
                    }
                    DropdownMenu(
                        expanded = createExpanded,
                        onDismissRequest = { createExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("New note") },
                            onClick = {
                                createExpanded = false
                                navController.navigate(Screen.Editor.routeForNew())
                            },
                            leadingIcon = { Icon(Icons.Default.Add, contentDescription = null) }
                        )
                        DropdownMenuItem(
                            text = { Text("New to-do") },
                            onClick = {
                                createExpanded = false
                                navController.navigate(Screen.Editor.routeForNewTodo())
                            },
                            leadingIcon = { Icon(Icons.Default.Checklist, contentDescription = null) }
                        )
                        DropdownMenuItem(
                            text = { Text("Voice capture") },
                            onClick = {
                                createExpanded = false
                                navController.navigate(Screen.VoiceCapture.route)
                            },
                            leadingIcon = { Icon(Icons.Default.Mic, contentDescription = null) }
                        )
                    }
                }
                ExtendedFloatingActionButton(
                    onClick = openTodayEditor,
                    icon = {
                        if (isOpeningToday) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Default.CalendarToday, contentDescription = null)
                    },
                    text = { Text("Add to today") }
                )
            }
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding).pullRefresh(pullRefreshState)) {
        Column(modifier = Modifier.fillMaxSize()) {
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
                                "Notes sync automatically in the background once GitHub is configured. Tap Add to today to start one."
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
                                    if (item.isPinned) {
                                        Icon(Icons.Default.PushPin, contentDescription = "Pinned")
                                    }
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
        PullRefreshIndicator(
            refreshing = isRefreshing,
            state = pullRefreshState,
            modifier = Modifier.align(androidx.compose.ui.Alignment.TopCenter)
        )
        }
    }
}

internal fun noteFolderLabel(item: com.specular.android.domain.model.NoteListItem): String? =
    item.path.substringBefore('/', missingDelimiterValue = "")
        .takeIf { it.isNotBlank() && !it.equals("assets", ignoreCase = true) && !it.equals("attachments", ignoreCase = true) }

internal const val DELETED_NOTE_ID = "deleted_note_id"
internal const val DELETED_NOTE_TITLE = "deleted_note_title"
