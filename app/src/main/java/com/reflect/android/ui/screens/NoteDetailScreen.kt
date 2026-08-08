package com.specular.android.ui.screens

import android.text.method.LinkMovementMethod
import android.text.Spannable
import android.text.style.ClickableSpan
import android.text.style.URLSpan
import android.util.TypedValue
import android.widget.TextView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import coil.compose.AsyncImage
import io.noties.markwon.Markwon
import io.noties.markwon.ext.tasklist.TaskListPlugin
import io.noties.markwon.ext.tasklist.TaskListSpan
import com.specular.android.ui.navigation.Screen
import com.specular.android.data.local.countTodoItems
import com.specular.android.data.local.NoteLinkPathResolver
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
    var showActions by remember { mutableStateOf(false) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }

    LaunchedEffect(vm) {
        vm.deletedNotes.collect { deleted ->
            navController.previousBackStackEntry?.savedStateHandle?.apply {
                set(DELETED_NOTE_ID, deleted.id)
                set(DELETED_NOTE_TITLE, deleted.title)
            }
            navController.popBackStack()
        }
    }

    LaunchedEffect(vm) {
        vm.linkedNoteIds.collect { linkedNoteId ->
            navController.navigate(Screen.Detail.routeFor(linkedNoteId))
        }
    }

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
                    Box {
                        IconButton(onClick = { showActions = true }) {
                            Icon(Icons.Default.MoreVert, "More actions")
                        }
                        DropdownMenu(
                            expanded = showActions,
                            onDismissRequest = { showActions = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Delete note") },
                                onClick = {
                                    showActions = false
                                    showDeleteConfirmation = true
                                },
                                leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null) }
                            )
                        }
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
                val isRegenerating by vm.isRegenerating.collectAsState()
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = n.snippet ?: "No snippet available",
                        fontStyle = FontStyle.Italic,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f)
                    )
                    if (isRegenerating) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        IconButton(onClick = { vm.regenerateSnippet(id) }) {
                            Icon(Icons.Default.Refresh, contentDescription = "Regenerate snippet")
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                if (n.isConflict) {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                        Text("Conflict — this note has a conflicting copy. Resolve in editor.", modifier = Modifier.padding(12.dp))
                    }
                    Spacer(Modifier.height(12.dp))
                }
                // Render markdown in chunks so inline images can continue to use Coil.
                // The title is already shown in the app bar; avoid rendering the note's
                // leading H1 a second time while leaving the stored markdown unchanged.
                val displayMarkdown = n.bodyMarkdown.replaceFirst(
                    Regex("""^\s*#\s+[^\r\n]+(?:\r?\n|$)"""),
                    ""
                )
                val imagePattern = Regex("""!\[(.*?)\]\((.*?)\)""")
                val matches = imagePattern.findAll(displayMarkdown).toList()
                var cursor = 0
                var taskOffset = 0

                matches.forEach { match ->
                    val markdownBeforeImage = displayMarkdown.substring(cursor, match.range.first)
                    MarkdownText(
                        markdown = markdownBeforeImage,
                        taskOffset = taskOffset,
                        onTaskClick = { taskIndex -> vm.toggleTask(id, taskIndex) },
                        onLinkClick = { destination ->
                            NoteLinkPathResolver.resolve(n.path, destination)?.let(vm::openLinkedNote) != null
                        }
                    )
                    taskOffset += countTodoItems(markdownBeforeImage)

                    val alt = match.groupValues[1]
                    val url = match.groupValues[2]
                    if (url.startsWith("assets/") || url.startsWith("http") || url.startsWith("file:")) {
                        Spacer(Modifier.height(8.dp))
                        AsyncImage(model = url, contentDescription = alt, modifier = Modifier.fillMaxWidth())
                    } else {
                        // Keep unsupported image destinations readable without displaying syntax.
                        MarkdownText(alt.ifBlank { "Image" }, taskOffset, onTaskClick = { }, onLinkClick = { false })
                    }

                    cursor = match.range.last + 1
                }

                val markdownAfterImages = displayMarkdown.substring(cursor)
                MarkdownText(
                    markdown = markdownAfterImages,
                    taskOffset = taskOffset,
                    onTaskClick = { taskIndex -> vm.toggleTask(id, taskIndex) },
                    onLinkClick = { destination ->
                        NoteLinkPathResolver.resolve(n.path, destination)?.let(vm::openLinkedNote) != null
                    }
                )
            }
        }
    }

    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = { Text("Delete note?") },
            text = {
                Text("This removes \"${note?.title.orEmpty()}\" from this device and GitHub the next time you sync.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirmation = false
                        vm.deleteNote(id)
                    }
                ) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) { Text("Cancel") }
            }
        )
    }
}

@Composable
private fun MarkdownText(
    markdown: String,
    taskOffset: Int,
    onTaskClick: (Int) -> Unit,
    onLinkClick: (String) -> Boolean
) {
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
            rendered.getSpans(0, rendered.length, URLSpan::class.java)
                .forEach { linkSpan ->
                    val start = rendered.getSpanStart(linkSpan)
                    val end = rendered.getSpanEnd(linkSpan)
                    if (start >= 0 && end > start) {
                        val flags = rendered.getSpanFlags(linkSpan)
                        rendered.removeSpan(linkSpan)
                        rendered.setSpan(
                            object : ClickableSpan() {
                                override fun onClick(widget: View) {
                                    if (!onLinkClick(linkSpan.url)) linkSpan.onClick(widget)
                                }

                                override fun updateDrawState(ds: android.text.TextPaint) {
                                    linkSpan.updateDrawState(ds)
                                }
                            },
                            start,
                            end,
                            flags
                        )
                    }
                }
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
