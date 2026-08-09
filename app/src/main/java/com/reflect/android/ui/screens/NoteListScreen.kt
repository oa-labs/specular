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
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Close
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
import androidx.compose.ui.Alignment
import androidx.compose.foundation.shape.RoundedCornerShape
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
    var showViewOptions by remember { mutableStateOf(false) }
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
                    if (isRefreshing) {
                        Box(
                            modifier = Modifier.size(48.dp),
                            contentAlignment = androidx.compose.ui.Alignment.Center
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        }
                    }
                    IconButton(onClick = { navController.navigate(Screen.Todos.route) }) {
                        Icon(Icons.Default.Checklist, "View todos")
                    }
                    IconButton(onClick = openTodayEditor, enabled = !isOpeningToday) {
                        if (isOpeningToday) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Default.CalendarToday, "Open today's note")
                        }
                    }
                    IconButton(onClick = { navController.navigate(Screen.Search.route) }) { Icon(Icons.Default.Search, "Search") }
                    Box {
                        IconButton(onClick = { overflowExpanded = true }) {
                            BadgedBox(
                                badge = {
                                    if (deselectedFolders.isNotEmpty()) {
                                        Badge(containerColor = MaterialTheme.colorScheme.primary)
                                    }
                                }
                            ) {
                                Icon(Icons.Default.MoreVert, "More actions")
                            }
                        }
                        DropdownMenu(
                            expanded = overflowExpanded,
                            onDismissRequest = { overflowExpanded = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("View options") },
                                onClick = {
                                    overflowExpanded = false
                                    showViewOptions = true
                                },
                                leadingIcon = { Icon(Icons.Default.Tune, contentDescription = null) }
                            )
                            HorizontalDivider()
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
                if (createExpanded) {
                    ExtendedFloatingActionButton(
                        onClick = {
                            createExpanded = false
                            navController.navigate(Screen.Editor.routeForNew())
                        },
                        icon = { Icon(Icons.Default.Add, contentDescription = null) },
                        text = { Text("New note") },
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    ExtendedFloatingActionButton(
                        onClick = {
                            createExpanded = false
                            navController.navigate(Screen.Editor.routeForNewTodo())
                        },
                        icon = { Icon(Icons.Default.Checklist, contentDescription = null) },
                        text = { Text("New to-do") },
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    ExtendedFloatingActionButton(
                        onClick = {
                            createExpanded = false
                            navController.navigate(Screen.VoiceCapture.route)
                        },
                        icon = { Icon(Icons.Default.Mic, contentDescription = null) },
                        text = { Text("Voice capture") },
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                SmallFloatingActionButton(
                    onClick = { createExpanded = !createExpanded },
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant
                ) {
                    Icon(
                        if (createExpanded) Icons.Default.Close else Icons.Default.Add,
                        if (createExpanded) "Close create menu" else "Create new item"
                    )
                }
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
                                "Notes sync automatically in the background once GitHub is configured. Tap the calendar to start today’s note."
                            } else {
                                "Open the menu to select one or more folders."
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().weight(1f),
                    // Keep text and metadata out of the floating create button's hit area.
                    contentPadding = PaddingValues(end = 72.dp, bottom = 88.dp)
                ) {
                    items(notes, key = { it.id }) { item ->
                        ListItem(
                            headlineContent = {
                                Text(
                                    item.title,
                                    style = MaterialTheme.typography.titleMedium,
                                    maxLines = 2
                                )
                            },
                            supportingContent = {
                                Row(
                                    verticalAlignment = Alignment.Top,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    noteFolderLabel(item)?.let { label -> NoteTypeChip(label) }
                                    item.snippet?.takeIf { it.isNotBlank() }?.let { snippet ->
                                        Text(
                                            snippet,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            maxLines = 2,
                                            modifier = Modifier.weight(1f, fill = false)
                                        )
                                    }
                                }
                            },
                            trailingContent = {
                                Row {
                                    if (item.isPinned) {
                                        Icon(Icons.Default.PushPin, contentDescription = "Pinned")
                                    }
                                    if (item.isDirty) Badge { Text("•") }
                                    if (item.isConflict) Badge(containerColor = MaterialTheme.colorScheme.error) { Text("!") }
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

    if (showViewOptions) {
        ModalBottomSheet(
            onDismissRequest = { showViewOptions = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 24.dp, end = 24.dp, bottom = 32.dp)
            ) {
                Text("View options", style = MaterialTheme.typography.headlineSmall)
                Text(
                    "Sort and choose the folders shown on your home screen.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp, bottom = 16.dp)
                )
                Text("Sort", style = MaterialTheme.typography.titleSmall)
                SortOption(
                    label = "Last updated",
                    selected = sort == NoteSort.LAST_UPDATED,
                    onClick = { vm.setSort(NoteSort.LAST_UPDATED) }
                )
                SortOption(
                    label = "Title, A–Z",
                    selected = sort == NoteSort.ALPHABETICAL,
                    onClick = { vm.setSort(NoteSort.ALPHABETICAL) }
                )
                if (folders.isNotEmpty()) {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.FilterList, contentDescription = null)
                        Spacer(Modifier.width(12.dp))
                        Text("Folders", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                        if (deselectedFolders.isNotEmpty()) {
                            TextButton(onClick = vm::showAllFolders) { Text("Show all") }
                        }
                    }
                    folders.forEach { folder ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { vm.toggleFolder(folder) }
                                .padding(vertical = 8.dp),
                            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                        ) {
                            Checkbox(
                                checked = folder !in deselectedFolders,
                                onCheckedChange = { vm.toggleFolder(folder) }
                            )
                            Spacer(Modifier.width(12.dp))
                            Text(folder, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SortOption(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
    ) {
        RadioButton(selected = selected, onClick = onClick)
        Spacer(Modifier.width(12.dp))
        Text(label, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun NoteTypeChip(label: String) {
    Surface(
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
        contentColor = MaterialTheme.colorScheme.primary,
        shape = RoundedCornerShape(8.dp)
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
        )
    }
}

internal fun noteFolderLabel(item: com.specular.android.domain.model.NoteListItem): String? =
    item.path.substringBefore('/', missingDelimiterValue = "")
        .takeIf { it.isNotBlank() && !it.equals("assets", ignoreCase = true) && !it.equals("attachments", ignoreCase = true) }

internal const val DELETED_NOTE_ID = "deleted_note_id"
internal const val DELETED_NOTE_TITLE = "deleted_note_title"
