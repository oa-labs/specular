package com.specular.android.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
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
    val isNew = id == "__new__"
    LaunchedEffect(id) { if (!isNew) vm.load(id) }
    val title by vm.title.collectAsState()
    val body by vm.body.collectAsState()
    val saving by vm.saving.collectAsState()

    // Camera handling — writes to assets/pasted-<epoch>.jpg and inserts markdown
    val context = androidx.compose.ui.platform.LocalContext.current
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    val cameraLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        if (success && cameraUri != null) {
            vm.insertImage("assets/${cameraUri!!.lastPathSegment}")
        }
    }
    val launchCameraCapture = {
        cameraUri = FileProvider.getUriForFile(
            context, "${context.packageName}.fileprovider",
            File(
                context.getExternalFilesDir(Environment.DIRECTORY_PICTURES),
                "capture-${System.currentTimeMillis()}.jpg"
            )
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
            // Copy to assets and insert — simplified: insert original uri, FileStore handles copy on save
            vm.insertImage(uri.toString())
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (isNew) "New note" else "Edit") },
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
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            OutlinedTextField(value = title, onValueChange = { vm.setTitle(it) }, label = { Text("Title") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = body, onValueChange = { vm.setBody(it) },
                label = { Text("Markdown") },
                modifier = Modifier.fillMaxSize(),
                placeholder = { Text("Type [[ to link…\n![](assets/…) for images") }
            )
        }
    }
}
