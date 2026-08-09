package com.specular.android.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(navController: NavController, id: String, vm: EditorViewModel = hiltViewModel()) {
    val isNewNote = id == "__new__"
    val isNew = isNewNote || id == "__new_todo__"
    LaunchedEffect(id) {
        when {
            id == "__new_todo__" -> vm.prepareNewTodo()
            isNewNote -> vm.prepareNewNote()
            !isNew -> vm.load(id)
        }
    }
    val title by vm.title.collectAsState()
    val body by vm.body.collectAsState()
    val saving by vm.saving.collectAsState()
    val selectedFolder by vm.selectedFolder.collectAsState()
    val availableFolders by vm.availableFolders.collectAsState()
    var folderExpanded by remember { mutableStateOf(false) }
    val linkSuggestions by vm.linkSuggestions.collectAsState()
    val linkQuery = remember(body) {
        Regex("""\[\[([^\]\n]*)$""").find(body)?.groupValues?.get(1)?.trim().orEmpty()
    }
    val matchingLinks = remember(linkSuggestions, linkQuery) {
        if (linkQuery.isBlank()) emptyList()
        else linkSuggestions.filter { it.contains(linkQuery, ignoreCase = true) }.take(5)
    }

    // Camera/gallery images are copied into the mirrored repository's attachments/.
    val context = androidx.compose.ui.platform.LocalContext.current
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    val cameraLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        if (success && cameraUri != null) {
            vm.importImage(cameraUri!!)
        }
    }
    val launchCameraCapture = {
        cameraUri = FileProvider.getUriForFile(
            context, "${context.packageName}.fileprovider",
            File(
                context.getExternalFilesDir(Environment.DIRECTORY_PICTURES),
                "capture-${System.currentTimeMillis()}.jpg"
            ).also { it.parentFile?.mkdirs() }
        )
        cameraLauncher.launch(cameraUri!!)
    }
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) launchCameraCapture()
    }
    val galleryLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            vm.importImage(uri)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when {
                            id == "__new_todo__" -> "New to-do"
                            isNew -> "New note"
                            else -> "Edit"
                        }
                    )
                },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) { Icon(Icons.Default.ArrowBack, "Back") }
                },
                actions = {
                    IconButton(onClick = {
                        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                            launchCameraCapture()
                        } else {
                            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                        }
                    }) { Icon(Icons.Default.PhotoCamera, "Camera") }
                    IconButton(onClick = { galleryLauncher.launch("image/*") }) { Icon(Icons.Default.PhotoLibrary, "Gallery") }
                    if (saving) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    else IconButton(onClick = {
                        vm.save(isNew) { newId -> navController.popBackStack(); if (isNew) navController.navigate("detail/$newId") }
                    }) { Icon(Icons.Default.Done, "Save") }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                // Keep the editor's viewport above the on-screen keyboard.
                .imePadding()
                .padding(16.dp)
        ) {
            OutlinedTextField(value = title, onValueChange = { vm.setTitle(it) }, label = { Text("Title") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            if (isNewNote) {
                Box(modifier = Modifier.padding(top = 8.dp)) {
                    TextButton(onClick = { folderExpanded = true }) {
                        Text("Save to: ${selectedFolder ?: "Inbox"}")
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                    }
                    DropdownMenu(
                        expanded = folderExpanded,
                        onDismissRequest = { folderExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Inbox") },
                            onClick = {
                                vm.setFolder(null)
                                folderExpanded = false
                            },
                            trailingIcon = {
                                if (selectedFolder == null) Icon(Icons.Default.Check, contentDescription = null)
                            }
                        )
                        availableFolders.forEach { folder ->
                            DropdownMenuItem(
                                text = { Text(folder) },
                                onClick = {
                                    vm.setFolder(folder)
                                    folderExpanded = false
                                },
                                trailingIcon = {
                                    if (selectedFolder.equals(folder, ignoreCase = true)) {
                                        Icon(Icons.Default.Check, contentDescription = null)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.surfaceVariant,
                shape = MaterialTheme.shapes.small
            ) {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    EditorShortcut("Bold") { vm.insertMarkdown("**bold text**") }
                    EditorShortcut("Italic") { vm.insertMarkdown("_italic text_") }
                    EditorShortcut("List") { vm.insertMarkdown("- ") }
                    EditorShortcut("Task") { vm.insertMarkdown("- [ ] ") }
                    EditorShortcut("Link") { vm.insertMarkdown("[link text](https://)") }
                    EditorShortcut("Wiki link") { vm.insertMarkdown("[[") }
                }
            }
            if (matchingLinks.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                Text("Link to", style = MaterialTheme.typography.labelMedium)
                Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
                    matchingLinks.forEach { suggestion ->
                        AssistChip(
                            onClick = { vm.insertWikiLink(suggestion) },
                            label = { Text(suggestion) },
                            modifier = Modifier.padding(end = 6.dp)
                        )
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = body, onValueChange = { vm.setBody(it) },
                label = { Text("Markdown") },
                // A weighted height gives this field the remaining screen space, which
                // lets its built-in scroll behavior work when the IME is visible.
                modifier = Modifier.fillMaxWidth().weight(1f),
                placeholder = { Text("Type [[ to link…\nUse camera or gallery to add images") }
            )
        }
    }
}

@Composable
private fun EditorShortcut(label: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp)) {
        Text(label, maxLines = 1)
    }
}
