package com.specular.android.ui.screens

import android.text.method.LinkMovementMethod
import android.text.Spannable
import android.text.Layout
import android.text.style.ClickableSpan
import android.text.style.LeadingMarginSpan
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
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import coil.compose.AsyncImage
import io.noties.markwon.Markwon
import io.noties.markwon.AbstractMarkwonPlugin
import io.noties.markwon.core.MarkwonTheme
import io.noties.markwon.ext.tasklist.TaskListPlugin
import io.noties.markwon.ext.tasklist.TaskListItem
import io.noties.markwon.ext.tasklist.TaskListProps
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
                        style = MaterialTheme.typography.titleLarge.copy(
                            fontSize = 17.6.sp,
                            lineHeight = 22.4.sp
                        ),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) { Icon(Icons.Default.ArrowBack, "Back") }
                },
                actions = {
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
        },
        floatingActionButton = {
            SmallFloatingActionButton(
                onClick = { navController.navigate(Screen.Editor.routeFor(id)) }
            ) {
                Icon(Icons.Default.Edit, contentDescription = "Edit note")
            }
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
                    .padding(start = 20.dp, top = 16.dp, end = 20.dp, bottom = 96.dp)
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
    val markwon = remember(context, accentColor, textColor, dividerColor) {
        Markwon.builder(context)
            .usePlugin(PreviewMarkdownThemePlugin(context, accentColor, dividerColor))
            .usePlugin(TaskListPlugin.create(context))
            .usePlugin(AccessibleTaskListPlugin(context, accentColor, textColor))
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
            val taskSpans = rendered.getSpans(0, rendered.length, AccessibleTaskListSpan::class.java)
                .sortedBy { rendered.getSpanStart(it) }
            taskSpans.forEachIndexed { localIndex, taskSpan ->
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
            var pressedTask: AccessibleTaskListSpan? = null
            textView.setOnTouchListener { _, event ->
                val layout = textView.layout ?: return@setOnTouchListener false
                val line = layout.getLineForVertical(
                    (event.y - textView.totalPaddingTop + textView.scrollY).toInt().coerceAtLeast(0)
                )
                val task = rendered.getSpans(
                    layout.getLineStart(line),
                    layout.getLineEnd(line),
                    AccessibleTaskListSpan::class.java
                ).firstOrNull()
                // Text begins to the right of the task margin. Its full left margin
                // acts as a standard, forgiving tap target for the checkbox.
                val isTaskTarget = task != null && event.x <= layout.getLineLeft(line)
                when (event.actionMasked) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        pressedTask = task?.takeIf { isTaskTarget }
                        pressedTask != null
                    }
                    android.view.MotionEvent.ACTION_UP -> {
                        val pressed = pressedTask
                        pressedTask = null
                        if (pressed != null && pressed == task && isTaskTarget) {
                            taskSpans.indexOf(pressed).takeIf { it >= 0 }?.let { localIndex ->
                                onTaskClick(taskOffset + localIndex)
                            }
                            true
                        } else false
                    }
                    android.view.MotionEvent.ACTION_CANCEL -> {
                        pressedTask = null
                        false
                    }
                    else -> pressedTask != null
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
            .blockMargin((16f * density).roundToInt())
            .bulletWidth((16f * density).roundToInt())
            .bulletListItemStrokeWidth((1.5f * density).roundToInt())
            .listItemColor(accentColor)
    }
}

/** A fixed-size task control that remains accessible when reading text is compact. */
private class AccessibleTaskListSpan(
    private val done: Boolean,
    private val controlSize: Int,
    private val margin: Int,
    private val accentColor: Int,
    private val textColor: Int
) : LeadingMarginSpan {
    override fun getLeadingMargin(first: Boolean): Int = margin

    override fun drawLeadingMargin(
        canvas: android.graphics.Canvas,
        paint: android.graphics.Paint,
        x: Int,
        dir: Int,
        top: Int,
        baseline: Int,
        bottom: Int,
        text: CharSequence,
        start: Int,
        end: Int,
        first: Boolean,
        layout: Layout
    ) {
        if (!first || text !is Spannable || text.getSpanStart(this) != start) return
        val left = if (dir > 0) x + (margin - controlSize) / 2 else x - margin + (margin - controlSize) / 2
        val topOffset = top + ((bottom - top - controlSize) / 2)
        val rect = android.graphics.RectF(
            left.toFloat(),
            topOffset.toFloat(),
            (left + controlSize).toFloat(),
            (topOffset + controlSize).toFloat()
        )
        val savedColor = paint.color
        val savedStyle = paint.style
        val savedStrokeWidth = paint.strokeWidth
        val savedStrokeCap = paint.strokeCap
        paint.strokeWidth = controlSize / 10f
        if (done) {
            paint.style = android.graphics.Paint.Style.FILL
            paint.color = accentColor
            canvas.drawRoundRect(rect, controlSize / 5f, controlSize / 5f, paint)
            paint.style = android.graphics.Paint.Style.STROKE
            paint.strokeCap = android.graphics.Paint.Cap.ROUND
            paint.strokeWidth = controlSize / 9f
            paint.color = textColor
            val check = android.graphics.Path().apply {
                moveTo(left + controlSize * 0.23f, topOffset + controlSize * 0.52f)
                lineTo(left + controlSize * 0.43f, topOffset + controlSize * 0.72f)
                lineTo(left + controlSize * 0.78f, topOffset + controlSize * 0.30f)
            }
            canvas.drawPath(check, paint)
        } else {
            paint.style = android.graphics.Paint.Style.STROKE
            paint.color = accentColor
            canvas.drawRoundRect(rect, controlSize / 5f, controlSize / 5f, paint)
        }
        paint.color = savedColor
        paint.style = savedStyle
        paint.strokeWidth = savedStrokeWidth
        paint.strokeCap = savedStrokeCap
    }
}

/** Overrides Markwon's text-sized task control while retaining its task parser. */
private class AccessibleTaskListPlugin(
    context: android.content.Context,
    private val accentColor: Int,
    private val textColor: Int
) : AbstractMarkwonPlugin() {
    private val controlSize = (20f * context.resources.displayMetrics.density).roundToInt()
    private val margin = (36f * context.resources.displayMetrics.density).roundToInt()

    override fun configureSpansFactory(builder: io.noties.markwon.MarkwonSpansFactory.Builder) {
        builder.setFactory(TaskListItem::class.java) { _, props ->
            AccessibleTaskListSpan(
                done = TaskListProps.DONE.require(props),
                controlSize = controlSize,
                margin = margin,
                accentColor = accentColor,
                textColor = textColor
            )
        }
    }
}
