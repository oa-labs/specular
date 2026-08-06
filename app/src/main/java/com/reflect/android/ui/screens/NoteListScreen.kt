package com.reflect.android.ui.screens

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
import com.reflect.android.ui.navigation.Screen


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteListScreen(navController: NavController, vm: NoteListViewModel = hiltViewModel()) {
    val notes by vm.notes.collectAsState()
    val isSyncing by vm.isSyncing.collectAsState()

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
        if (notes.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = androidx.compose.ui.Alignment.Center) {
                Text("No notes yet — pull to sync or create one.", style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(notes, key = { it.id }) { item ->
                    ListItem(
                        headlineContent = { Text(item.title) },
                        supportingContent = { Text(item.snippet, maxLines = 2) },
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
