package com.specular.android.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavController
import com.specular.android.ui.navigation.Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceCaptureScreen(navController: NavController, vm: VoiceCaptureViewModel = hiltViewModel()) {
    val state by vm.state.collectAsState()
    val isConfigured by vm.isConfigured.collectAsState()
    var kind by remember { mutableStateOf(VoiceCaptureKind.THOUGHT) }
    val context = LocalContext.current
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) vm.startRecording()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Voice capture") },
                navigationIcon = {
                    IconButton(onClick = { vm.discard(); navController.popBackStack() }) {
                        Icon(Icons.Default.ArrowBack, "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                "Record a thought or to-do. You can review the transcript before it is added to today.",
                style = MaterialTheme.typography.bodyLarge
            )
            if (!isConfigured) {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Voice transcription is not configured", style = MaterialTheme.typography.titleSmall)
                        Text("Choose a voice provider and model in Settings before recording.")
                        TextButton(onClick = { navController.navigate(Screen.Settings.route) }) {
                            Text("Open settings")
                        }
                    }
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = kind == VoiceCaptureKind.THOUGHT,
                        onClick = { kind = VoiceCaptureKind.THOUGHT },
                        label = { Text("Thought") },
                        enabled = !state.recording && !state.transcribing && !state.saving
                    )
                    FilterChip(
                        selected = kind == VoiceCaptureKind.TODO,
                        onClick = { kind = VoiceCaptureKind.TODO },
                        label = { Text("To-do") },
                        enabled = !state.recording && !state.transcribing && !state.saving
                    )
                }

                state.error?.let { message ->
                    Text(message, color = MaterialTheme.colorScheme.error)
                }

                when {
                    state.transcribing -> Box(modifier = Modifier.fillMaxWidth().padding(vertical = 36.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            CircularProgressIndicator()
                            Text("Transcribing recording…")
                        }
                    }
                    state.transcript.isNotBlank() -> {
                        OutlinedTextField(
                            value = state.transcript,
                            onValueChange = vm::setTranscript,
                            label = { Text("Transcript") },
                            modifier = Modifier.fillMaxWidth().weight(1f),
                            enabled = !state.saving
                        )
                        Button(
                            onClick = {
                                vm.saveToToday(kind) { noteId ->
                                    navController.popBackStack()
                                    navController.navigate(Screen.Editor.routeFor(noteId))
                                }
                            },
                            enabled = !state.saving,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            if (state.saving) CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            else Text(if (kind == VoiceCaptureKind.TODO) "Add to-do to today" else "Add thought to today")
                        }
                        TextButton(onClick = vm::discard, enabled = !state.saving, modifier = Modifier.fillMaxWidth()) {
                            Text("Discard")
                        }
                    }
                    state.recording -> {
                        Box(modifier = Modifier.fillMaxWidth().padding(vertical = 36.dp), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Icon(Icons.Default.Mic, contentDescription = null, modifier = Modifier.size(56.dp), tint = MaterialTheme.colorScheme.error)
                                Text("Recording…", style = MaterialTheme.typography.titleLarge)
                            }
                        }
                        Button(onClick = vm::stopAndTranscribe, modifier = Modifier.fillMaxWidth()) {
                            Text("Stop and transcribe")
                        }
                    }
                    else -> {
                        Spacer(Modifier.weight(1f))
                        Button(
                            onClick = {
                                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                                    vm.startRecording()
                                } else {
                                    permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                }
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Icon(Icons.Default.Mic, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Start recording")
                        }
                    }
                }
            }
        }
    }
}
