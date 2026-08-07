package com.specular.android.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import coil.compose.AsyncImage
import com.specular.android.ui.navigation.Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteDetailScreen(navController: NavController, id: String, vm: NoteDetailViewModel = hiltViewModel()) {
    LaunchedEffect(id) { vm.load(id) }
    val note by vm.note.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(note?.title ?: "…") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) { Icon(Icons.Default.ArrowBack, "Back") }
                },
                actions = {
                    IconButton(onClick = { navController.navigate(Screen.Editor.routeFor(id)) }) {
                        Icon(Icons.Default.Edit, "Edit")
                    }
                }
            )
        }
    ) { padding ->
        val n = note
        if (n == null) {
            Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = androidx.compose.ui.Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            Column(modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp)) {
                if (n.isConflict) {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                        Text("Conflict — this note has a conflicting copy. Resolve in editor.", modifier = Modifier.padding(12.dp))
                    }
                    Spacer(Modifier.height(12.dp))
                }
                // Simple markdown preview — split on image syntax for inline asset preview
                val parts = Regex("""!\[(.*?)\]\((.*?)\)""").split(n.bodyMarkdown)
                val matches = Regex("""!\[(.*?)\]\((.*?)\)""").findAll(n.bodyMarkdown).toList()
                Text(n.bodyMarkdown, style = MaterialTheme.typography.bodyMedium)
                // Show inline images from assets/ via Coil (file:// or https)
                matches.forEach { m ->
                    val alt = m.groupValues[1]
                    val url = m.groupValues[2]
                    if (url.startsWith("assets/") || url.startsWith("http")) {
                        Spacer(Modifier.height(8.dp))
                        AsyncImage(model = url, contentDescription = alt, modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }
}
