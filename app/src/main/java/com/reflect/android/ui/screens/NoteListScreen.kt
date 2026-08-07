package com.specular.android.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
    val isSyncing by vm.isSyncing.collectAsState()
    val syncMessage by vm.syncMessage.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Specular") },
                actions = {
                    if (isSyncing) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    IconButton(onClick = { vm.sync() }) { Icon(Icons.Default.Refresh, "Sync") }
                    IconButton(onClick = { navController.navigate(Screen.Search.route) }) { Icon(Icons.Default.Search, "Search") }
                    IconButton(onClick = { navController.navigate(Screen.Settings.route) }) { Icon(Icons.Default.Settings, "Settings") }
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
            syncMessage?.let { message ->
                Card(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
                ) {
                    Text(
                        message,
                        modifier = Modifier.padding(12.dp),
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            if (notes.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize().weight(1f), contentAlignment = androidx.compose.ui.Alignment.Center) {
                    Column(horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
                        Text("No notes yet", style = MaterialTheme.typography.headlineSmall)
                        Text(
                            "Pull to sync from your GitHub repository or tap + to create one.",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(top = 8.dp)
                        )
                        if (isSyncing) {
                            CircularProgressIndicator(modifier = Modifier.padding(top = 16.dp))
                        }
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
                                    if (item.isDaily) Text(" daily", style = MaterialTheme.typography.labelSmall)
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
