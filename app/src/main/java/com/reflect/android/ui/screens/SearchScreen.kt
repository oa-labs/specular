package com.specular.android.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.specular.android.ui.navigation.Screen
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(navController: NavController, vm: SearchViewModel = hiltViewModel()) {
    var query by remember { mutableStateOf("") }
    val results by vm.results.collectAsState()
    val isSearching by vm.isSearching.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val savedStateHandle = navController.currentBackStackEntry?.savedStateHandle

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

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it; vm.search(it) },
                        placeholder = { Text("Search notes") },
                        singleLine = true,
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                        trailingIcon = {
                            if (query.isNotEmpty()) {
                                IconButton(onClick = { query = ""; vm.search("") }) {
                                    Icon(Icons.Default.Clear, "Clear search")
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(end = 8.dp)
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) { Icon(Icons.Default.ArrowBack, "Back") }
                }
            )
        }
    ) { padding ->
        when {
            query.isBlank() -> SearchEmptyState(
                title = "Search your notes",
                message = "Find matches in note titles and content.",
                modifier = Modifier.fillMaxSize().padding(padding)
            )
            isSearching && results.isEmpty() -> Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
            results.isEmpty() -> SearchEmptyState(
                title = "No matches",
                message = "Try a different word or phrase.",
                modifier = Modifier.fillMaxSize().padding(padding)
            )
            else -> {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp)
            ) {
                items(results, key = { it.id }) { item ->
                    ListItem(
                        headlineContent = { HighlightedText(item.title, query, style = MaterialTheme.typography.titleMedium) },
                        supportingContent = {
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                item.snippet?.takeIf { it.isNotBlank() }?.let {
                                    HighlightedText(it, query, maxLines = 2)
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    noteFolderLabel(item)?.let { folder ->
                                        Text(folder, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                                    }
                                    formatUpdatedAt(item.updatedAt)?.let { updated ->
                                        Text(updated, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
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
    }
}

@Composable
private fun SearchEmptyState(title: String, message: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.padding(32.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Default.Search,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(12.dp))
            Text(title, style = MaterialTheme.typography.titleLarge)
            Text(
                message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Composable
private fun HighlightedText(
    text: String,
    query: String,
    modifier: Modifier = Modifier,
    style: androidx.compose.ui.text.TextStyle = LocalTextStyle.current,
    maxLines: Int = Int.MAX_VALUE
) {
    val highlight = MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)
    val annotated = remember(text, query, highlight) {
        buildAnnotatedString {
            var cursor = 0
            while (cursor < text.length) {
                val match = text.indexOf(query, cursor, ignoreCase = true)
                if (match < 0) {
                    append(text.substring(cursor))
                    break
                }
                append(text.substring(cursor, match))
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, background = highlight)) {
                    append(text.substring(match, match + query.length))
                }
                cursor = match + query.length
            }
        }
    }
    Text(annotated, modifier = modifier, style = style, maxLines = maxLines)
}

private val SearchDateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("MMM d")

private fun formatUpdatedAt(updatedAt: Long): String? = updatedAt.takeIf { it > 0 }?.let {
    Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).format(SearchDateFormatter)
}
