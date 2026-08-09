package com.specular.android.ui.screens

import android.text.method.LinkMovementMethod
import android.text.Spannable
import android.text.style.ClickableSpan
import android.text.style.URLSpan
import android.util.TypedValue
import android.widget.TextView
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.DriveFileRenameOutline
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import coil.compose.AsyncImage
import io.noties.markwon.Markwon
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.core.MarkwonTheme
import io.noties.markwon.ext.tasklist.TaskListPlugin
import io.noties.markwon.ext.tasklist.TaskListSpan
import com.specular.android.ui.navigation.Screen
import com.specular.android.data.local.countTodoItems
import com.specular.android.data.local.NoteLinkPathResolver
import android.view.View
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteDetailScreen(
    navController: NavController,
    id: String,
    vm: NoteDetailViewModel = hiltViewModel()
) {
    LaunchedEffect(id) { vm.load(id) }
    val note by vm.note.collectAsState()
    // The note itself is unchanged when sync downloads an attachment. Observing
    // attachment writes lets imageModel retry as soon as the local file exists.
    val attachmentChangeToken by vm.attachmentChangeToken.collectAsState(initial = null)
    var showActions by remember { mutableStateOf(false) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var renamePath by remember { mutableStateOf("") }
    val renameError by vm.renameError.collectAsState()

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
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        note?.title ?: "…",
                        style = MaterialTheme.typography.titleLarge,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                },
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
                            note?.let { currentNote ->
                                DropdownMenuItem(
                                    text = { Text(if (currentNote.isPinned) "Unpin note" else "Pin note") },
                                    onClick = {
                                        showActions = false
                                        vm.setPinned(id, !currentNote.isPinned)
                                    },
                                    leadingIcon = { Icon(Icons.Default.PushPin, contentDescription = null) }
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Rename file") },
                                onClick = {
                                    showActions = false
                                    renamePath = note?.path.orEmpty()
                                    vm.clearRenameError()
                                    showRenameDialog = true
                                },
                                leadingIcon = {
                                    Icon(Icons.Default.DriveFileRenameOutline, contentDescription = null)
                                }
                            )
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
            // Read the token so Compose tracks it as a dependency of the rendered note.
            @Suppress("UNUSED_VARIABLE")
            val attachmentRefresh = attachmentChangeToken
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 16.dp)
            ) {
                val isRegenerating by vm.isRegenerating.collectAsState()
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "Summary",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.weight(1f)
                            )
                            if (isRegenerating) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            } else {
                                IconButton(onClick = { vm.regenerateSnippet(id) }, modifier = Modifier.size(32.dp)) {
                                    Icon(Icons.Default.Refresh, contentDescription = "Regenerate summary", modifier = Modifier.size(20.dp))
                                }
                            }
                        }
                        Text(
                            text = n.snippet ?: "No summary available",
                            style = MaterialTheme.typography.bodyLarge,
                            fontStyle = FontStyle.Italic,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 4.dp)
                        )
                    }
                }
                Spacer(Modifier.height(20.dp))
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
                    val imageModel = vm.imageModel(n.path, url)
                    if (imageModel != null) {
                        Spacer(Modifier.height(8.dp))
                        AsyncImage(model = imageModel, contentDescription = alt, modifier = Modifier.fillMaxWidth())
                    } else {
                        MarkdownText(
                            alt.ifBlank { "Image unavailable: $url" },
                            taskOffset,
                            onTaskClick = { },
                            onLinkClick = { false }
                        )
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

    if (showRenameDialog) {
        AlertDialog(
            onDismissRequest = {
                showRenameDialog = false
                vm.clearRenameError()
            },
            title = { Text("Rename note file") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Use a repository-relative Markdown filename. Links are not rewritten.")
                    OutlinedTextField(
                        value = renamePath,
                        onValueChange = {
                            renamePath = it
                            vm.clearRenameError()
                        },
                        label = { Text("Path") },
                        supportingText = renameError?.let { { Text(it, color = MaterialTheme.colorScheme.error) } },
                        isError = renameError != null,
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    vm.renameNote(id, renamePath) { showRenameDialog = false }
                }) { Text("Rename") }
            },
            dismissButton = {
                TextButton(onClick = {
                    showRenameDialog = false
                    vm.clearRenameError()
                }) { Text("Cancel") }
            }
        )
    }
}

@Composable
/** Renders Markdown shared by note details and compact task-list rows. */
internal fun MarkdownText(
    markdown: String,
    taskOffset: Int,
    onTaskClick: (Int) -> Unit,
    onLinkClick: (String) -> Boolean,
    onBodyClick: (() -> Unit)? = null
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val textColor = MaterialTheme.colorScheme.onBackground.toArgb()
    val accentColor = MaterialTheme.colorScheme.primary.toArgb()
    val dividerColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.24f).toArgb()
    val markwon = remember(context, accentColor, dividerColor) {
        Markwon.builder(context)
            .usePlugin(PreviewMarkdownThemePlugin(context, accentColor, dividerColor))
            .usePlugin(TaskListPlugin.create(context))
            .build()
    }

    AndroidView(
        modifier = Modifier.fillMaxWidth(),
        factory = {
            TextView(it).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                setTextColor(textColor)
                setLineSpacing(4f * resources.displayMetrics.density, 1f)
                includeFontPadding = false
                movementMethod = LinkMovementMethod.getInstance()
                linksClickable = true
                setPadding(0, 0, 0, 0)
            }
        },
        update = { textView ->
            textView.setTextColor(textColor)
            textView.setOnClickListener(
                onBodyClick?.let { bodyClick -> View.OnClickListener { bodyClick() } }
            )
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

/** Keeps Markdown headings and lists compact enough for an in-app reading view. */
private class PreviewMarkdownThemePlugin(
    context: android.content.Context,
    private val accentColor: Int,
    private val dividerColor: Int
) : AbstractMarkwonPlugin() {
    private val density = context.resources.displayMetrics.density

    override fun configureTheme(builder: MarkwonTheme.Builder) {
        builder
            .headingTextSizeMultipliers(floatArrayOf(1.45f, 1.3f, 1.18f, 1.08f, 1f, 1f))
            .headingBreakHeight(0)
            .headingBreakColor(dividerColor)
            .thematicBreakHeight((1f * density).roundToInt())
            .thematicBreakColor(dividerColor)
            .blockMargin((8f * density).roundToInt())
            .bulletWidth((5f * density).roundToInt())
            .bulletListItemStrokeWidth((1f * density).roundToInt())
            .listItemColor(accentColor)
    }
}
