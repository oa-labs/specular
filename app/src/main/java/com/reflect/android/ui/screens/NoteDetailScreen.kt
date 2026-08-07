package com.specular.android.ui.screens

import android.text.method.LinkMovementMethod
import android.text.Spannable
import android.text.style.ClickableSpan
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
import io.noties.markwon.ext.tasklist.TaskListSpan
import com.specular.android.ui.navigation.Screen
import android.view.View

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteDetailScreen(
    navController: NavController,
    id: String,
    vm: NoteDetailViewModel = hiltViewModel()
) {
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
                var taskOffset = 0

                matches.forEach { match ->
                    val markdownBeforeImage = n.bodyMarkdown.substring(cursor, match.range.first)
                    MarkdownText(markdownBeforeImage, taskOffset) { taskIndex -> vm.toggleTask(id, taskIndex) }
                    taskOffset += countTaskItems(markdownBeforeImage)

                    val alt = match.groupValues[1]
                    val url = match.groupValues[2]
                    if (url.startsWith("assets/") || url.startsWith("http") || url.startsWith("file:")) {
                        Spacer(Modifier.height(8.dp))
                        AsyncImage(model = url, contentDescription = alt, modifier = Modifier.fillMaxWidth())
                    } else {
                        // Keep unsupported image destinations readable without displaying syntax.
                        MarkdownText(alt.ifBlank { "Image" }, taskOffset) { }
                    }

                    cursor = match.range.last + 1
                }

                val markdownAfterImages = n.bodyMarkdown.substring(cursor)
                MarkdownText(markdownAfterImages, taskOffset) { taskIndex -> vm.toggleTask(id, taskIndex) }
            }
        }
    }
}

@Composable
private fun MarkdownText(markdown: String, taskOffset: Int, onTaskClick: (Int) -> Unit) {
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

            val rendered = textView.text as? Spannable ?: return@AndroidView
            rendered.getSpans(0, rendered.length, TaskListSpan::class.java)
                .sortedBy { rendered.getSpanStart(it) }
                .forEachIndexed { localIndex, taskSpan ->
                    val start = rendered.getSpanStart(taskSpan)
                    val end = rendered.getSpanEnd(taskSpan)
                    if (start >= 0 && end > start) {
                        rendered.setSpan(
                            object : ClickableSpan() {
                                override fun onClick(widget: View) {
                                    onTaskClick(taskOffset + localIndex)
                                }

                                override fun updateDrawState(ds: android.text.TextPaint) {
                                    // Keep task text styled as normal Markdown, without an underline.
                                }
                            },
                            start,
                            end,
                            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    }
                }
        }
    )
}
