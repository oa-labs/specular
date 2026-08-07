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
    val isTesting by vm.isTesting.collectAsState()
    val statusMessage by vm.statusMessage.collectAsState()

    var tokenInput by remember(token) { mutableStateOf(token ?: "") }
    var ownerInput by remember(owner) { mutableStateOf(owner ?: "") }
    var repoInput by remember(repo) { mutableStateOf(repo ?: "") }

    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    LaunchedEffect(statusMessage) {
        statusMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            vm.clearStatus()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = { navController.popBackStack() }) {
                        Icon(Icons.Default.ArrowBack, "Back")
                    }
                }
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "GitHub Sync — github.com only, no telemetry",
                style = MaterialTheme.typography.labelMedium
            )

            OutlinedTextField(
                value = tokenInput,
                onValueChange = { tokenInput = it },
                label = { Text("GitHub token (OAuth or PAT)") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = ownerInput,
                onValueChange = { ownerInput = it },
                label = { Text("Repo owner") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = repoInput,
                onValueChange = { repoInput = it },
                label = { Text("Repo name") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { vm.save(tokenInput, ownerInput, repoInput) },
                    modifier = Modifier.weight(1f),
                    enabled = !isTesting
                ) {
                    Text("Save")
                }

                Button(
                    onClick = { vm.testConnection() },
                    modifier = Modifier.weight(1f),
                    enabled = !isTesting && vm.isConfigured()
                ) {
                    Text(if (isTesting) "Testing..." else "Test Connection")
                }
            }

            OutlinedButton(
                onClick = {
                    vm.clear()
                    tokenInput = ""
                    ownerInput = ""
                    repoInput = ""
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Clear & disconnect")
            }

            if (vm.isConfigured() && statusMessage?.contains("Successfully") == true) {
                Button(
                    onClick = { navController.popBackStack() },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                ) {
                    Text("Connection Successful — Return to Notes")
                }
            }

            if (statusMessage != null) {
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = if (statusMessage!!.contains("Successfully") || statusMessage!!.contains("connected"))
                            MaterialTheme.colorScheme.primaryContainer
                        else
                            MaterialTheme.colorScheme.errorContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        statusMessage!!,
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (statusMessage!!.contains("Successfully") || statusMessage!!.contains("connected"))
                            MaterialTheme.colorScheme.onPrimaryContainer
                        else
                            MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }

            Text(
                "Token is stored securely. Use a fine-grained PAT with 'Contents: read & write' permissions. After saving, the app will test the connection and return to the note list if successful.",
                style = MaterialTheme.typography.bodySmall
            )

            Text(
                "Build: gmsFree — no Play Services. Updates via GitHub Releases.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary
            )
        }
    }
}

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val auth: GitHubAuth
) : ViewModel() {

    private val _token = MutableStateFlow(auth.token)
    val token: StateFlow<String?> = _token.asStateFlow()

    private val _owner = MutableStateFlow(auth.repoOwner)
    val owner: StateFlow<String?> = _owner.asStateFlow()

    private val _repo = MutableStateFlow(auth.repoName)
    val repo: StateFlow<String?> = _repo.asStateFlow()

    private val _isTesting = MutableStateFlow(false)
    val isTesting: StateFlow<Boolean> = _isTesting.asStateFlow()

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    fun isConfigured(): Boolean = auth.isConfigured()

    fun save(tokenInput: String, ownerInput: String, repoInput: String) {
        auth.token = tokenInput.ifBlank { null }
        auth.repoOwner = ownerInput.ifBlank { null }
        auth.repoName = repoInput.ifBlank { null }

        _token.value = auth.token
        _owner.value = auth.repoOwner
        _repo.value = auth.repoName

        _statusMessage.value = if (auth.isConfigured()) {
            "Settings saved. Tap 'Test Connection' to verify."
        } else {
            "Settings saved. Please fill in all three fields."
        }
    }

    fun testConnection() {
        viewModelScope.launch {
            _isTesting.value = true
            _statusMessage.value = "Testing connection to GitHub..."

            try {
                val result = auth.testConnection()
                _statusMessage.value = result
            } catch (e: Exception) {
                val message = when (e) {
                    is IllegalArgumentException -> e.message ?: "Invalid configuration"
                    is IllegalStateException -> e.message ?: "Configuration error"
                    else -> "Connection failed: ${e.message}"
                }
                _statusMessage.value = message
            } finally {
                _isTesting.value = false
            }
        }
    }

    fun clear() {
        auth.clear()
        _token.value = null
        _owner.value = null
        _repo.value = null
        _statusMessage.value = "Configuration cleared"
    }

    fun clearStatus() {
        _statusMessage.value = null
    }
}
