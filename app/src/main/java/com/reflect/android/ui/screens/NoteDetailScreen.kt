package com.specular.android.ui.screens

import android.text.method.LinkMovementMethod
import android.util.TypedValue
import android.widget.TextView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import coil.compose.AsyncImage
import io.noties.markwon.Markwon
import io.noties.markwon.ext.tasklist.TaskListPlugin
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
                // Render markdown in chunks so inline images can continue to use Coil.
                val imagePattern = Regex("""!\[(.*?)\]\((.*?)\)""")
                val matches = imagePattern.findAll(n.bodyMarkdown).toList()
                var cursor = 0

                matches.forEach { match ->
                    MarkdownText(n.bodyMarkdown.substring(cursor, match.range.first))

                    val alt = match.groupValues[1]
                    val url = match.groupValues[2]
                    if (url.startsWith("assets/") || url.startsWith("http") || url.startsWith("file:")) {
                        Spacer(Modifier.height(8.dp))
                        AsyncImage(model = url, contentDescription = alt, modifier = Modifier.fillMaxWidth())
                    } else {
                        // Keep unsupported image destinations readable without displaying syntax.
                        MarkdownText(alt.ifBlank { "Image" })
                    }

                    cursor = match.range.last + 1
                }

                MarkdownText(n.bodyMarkdown.substring(cursor))
            }
        }
    }
}

@Composable
private fun MarkdownText(markdown: String) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val markwon = remember(context) {
        Markwon.builder(context)
            .usePlugin(TaskListPlugin.create(context))
            .build()
    }
    val textColor = MaterialTheme.colorScheme.onBackground.toArgb()

    AndroidView(
        modifier = Modifier.fillMaxWidth(),
        factory = {
            TextView(it).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setTextColor(textColor)
                movementMethod = LinkMovementMethod.getInstance()
                linksClickable = true
                setPadding(0, 0, 0, 0)
            }
        },
        update = { textView ->
            textView.setTextColor(textColor)
            markwon.setMarkdown(textView, markdown)
        }
    )
}
