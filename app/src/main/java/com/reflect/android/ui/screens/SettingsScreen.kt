package com.specular.android.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import com.specular.android.data.remote.GitHubAuth
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(navController: NavController, vm: SettingsViewModel = hiltViewModel()) {
    val token by vm.token.collectAsState()
    val owner by vm.owner.collectAsState()
    val repo by vm.repo.collectAsState()
    var tokenInput by remember(token) { mutableStateOf(token ?: "") }
    var ownerInput by remember(owner) { mutableStateOf(owner ?: "") }
    var repoInput by remember(repo) { mutableStateOf(repo ?: "") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = { IconButton(onClick = { navController.popBackStack() }) { Icon(Icons.Default.ArrowBack, "Back") } }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("GitHub Sync — github.com only, no telemetry", style = MaterialTheme.typography.labelMedium)
            OutlinedTextField(value = tokenInput, onValueChange = { tokenInput = it }, label = { Text("GitHub token (OAuth or PAT)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(value = ownerInput, onValueChange = { ownerInput = it }, label = { Text("Repo owner") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            OutlinedTextField(value = repoInput, onValueChange = { repoInput = it }, label = { Text("Repo name") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            Button(onClick = { vm.save(tokenInput, ownerInput, repoInput) }, modifier = Modifier.fillMaxWidth()) { Text("Save") }
            OutlinedButton(onClick = { vm.clear(); tokenInput = ""; ownerInput = ""; repoInput = "" }, modifier = Modifier.fillMaxWidth()) { Text("Clear & disconnect") }
            Text("Token is stored in EncryptedSharedPreferences and excluded from backup. Use a fine-grained PAT with Contents: read & write for the reflect repo, or complete the OAuth flow (client id not yet configured — PAT is the current path).", style = MaterialTheme.typography.bodySmall)
            Text("Build: gmsFree — no Play Services. Updates via GitHub Releases.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
        }
    }
}

@HiltViewModel
class SettingsViewModel @Inject constructor(private val auth: GitHubAuth) : ViewModel() {
    private val _token = MutableStateFlow(auth.token)
    val token: StateFlow<String?> = _token.asStateFlow()
    private val _owner = MutableStateFlow(auth.repoOwner)
    val owner: StateFlow<String?> = _owner.asStateFlow()
    private val _repo = MutableStateFlow(auth.repoName)
    val repo: StateFlow<String?> = _repo.asStateFlow()

    fun save(t: String, o: String, r: String) {
        auth.token = t.ifBlank { null }
        auth.repoOwner = o.ifBlank { null }
        auth.repoName = r.ifBlank { null }
        _token.value = auth.token
        _owner.value = auth.repoOwner
        _repo.value = auth.repoName
    }

    fun clear() {
        auth.clear()
        _token.value = null
        _owner.value = null
        _repo.value = null
    }
}
