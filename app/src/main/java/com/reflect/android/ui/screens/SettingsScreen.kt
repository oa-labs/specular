package com.specular.android.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.AiProviderSettings
import com.specular.android.sync.SyncEngine
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
    val aiUrl by vm.aiUrl.collectAsState()
    val aiApiKey by vm.aiApiKey.collectAsState()
    val aiModelId by vm.aiModelId.collectAsState()
    val isTesting by vm.isTesting.collectAsState()
    val statusMessage by vm.statusMessage.collectAsState()

    var tokenInput by remember(token) { mutableStateOf(token ?: "") }
    var ownerInput by remember(owner) { mutableStateOf(owner ?: "") }
    var repoInput by remember(repo) { mutableStateOf(repo ?: "") }
    var aiUrlInput by remember(aiUrl) { mutableStateOf(aiUrl ?: "") }
    var aiApiKeyInput by remember(aiApiKey) { mutableStateOf(aiApiKey ?: "") }
    var aiModelIdInput by remember(aiModelId) { mutableStateOf(aiModelId ?: "") }

    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(statusMessage) {
        statusMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
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
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                "GitHub Sync and AI snippets — no telemetry",
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
                    onClick = {
                        vm.save(tokenInput, ownerInput, repoInput, aiUrlInput, aiApiKeyInput, aiModelIdInput)
                    },
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

            HorizontalDivider()
            Text("AI snippets", style = MaterialTheme.typography.titleMedium)
            Text(
                "Configure an OpenAI-compatible chat-completions URL. Snippets are saved as markdown metadata and generated only for notes that do not already have one.",
                style = MaterialTheme.typography.bodySmall
            )

            OutlinedTextField(
                value = aiUrlInput,
                onValueChange = { aiUrlInput = it },
                label = { Text("AI provider URL") },
                placeholder = { Text("https://api.example.com/v1/chat/completions") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedTextField(
                value = aiApiKeyInput,
                onValueChange = { aiApiKeyInput = it },
                label = { Text("AI API key") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation()
            )

            OutlinedTextField(
                value = aiModelIdInput,
                onValueChange = { aiModelIdInput = it },
                label = { Text("AI model id") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            OutlinedButton(
                onClick = {
                    vm.clear()
                    tokenInput = ""
                    ownerInput = ""
                    repoInput = ""
                    aiUrlInput = ""
                    aiApiKeyInput = ""
                    aiModelIdInput = ""
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
                "Credentials are stored securely. Use a fine-grained PAT with 'Contents: read & write' permissions. AI requests send note content to the provider URL you configure.",
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
    private val auth: GitHubAuth,
    private val syncEngine: SyncEngine,
    private val aiSettings: AiProviderSettings
) : ViewModel() {

    private val _token = MutableStateFlow(auth.token)
    val token: StateFlow<String?> = _token.asStateFlow()

    private val _owner = MutableStateFlow(auth.repoOwner)
    val owner: StateFlow<String?> = _owner.asStateFlow()

    private val _repo = MutableStateFlow(auth.repoName)
    val repo: StateFlow<String?> = _repo.asStateFlow()

    private val _aiUrl = MutableStateFlow(aiSettings.config.value?.url)
    val aiUrl: StateFlow<String?> = _aiUrl.asStateFlow()

    private val _aiApiKey = MutableStateFlow(aiSettings.config.value?.apiKey)
    val aiApiKey: StateFlow<String?> = _aiApiKey.asStateFlow()

    private val _aiModelId = MutableStateFlow(aiSettings.config.value?.modelId)
    val aiModelId: StateFlow<String?> = _aiModelId.asStateFlow()

    private val _isTesting = MutableStateFlow(false)
    val isTesting: StateFlow<Boolean> = _isTesting.asStateFlow()

    private val _statusMessage = MutableStateFlow<String?>(null)
    val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

    fun isConfigured(): Boolean = auth.isConfigured()

    fun save(
        tokenInput: String,
        ownerInput: String,
        repoInput: String,
        aiUrlInput: String,
        aiApiKeyInput: String,
        aiModelIdInput: String
    ) {
        auth.token = tokenInput.ifBlank { null }
        auth.repoOwner = ownerInput.ifBlank { null }
        auth.repoName = repoInput.ifBlank { null }
        if (aiUrlInput.isBlank() && aiApiKeyInput.isBlank() && aiModelIdInput.isBlank()) {
            aiSettings.clear()
        } else {
            aiSettings.save(aiUrlInput, aiApiKeyInput, aiModelIdInput)
        }

        _token.value = auth.token
        _owner.value = auth.repoOwner
        _repo.value = auth.repoName
        _aiUrl.value = aiSettings.config.value?.url
        _aiApiKey.value = aiSettings.config.value?.apiKey
        _aiModelId.value = aiSettings.config.value?.modelId

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
                _statusMessage.value = "$result. Syncing notes..."
                when (val syncResult = syncEngine.sync()) {
                    is SyncEngine.Result.Success -> {
                        _statusMessage.value = "$result. Notes synced. Return to Notes."
                    }
                    is SyncEngine.Result.NotConfigured -> {
                        _statusMessage.value = "Connection succeeded, but sync is not configured."
                    }
                    is SyncEngine.Result.Error -> {
                        _statusMessage.value = "Connection succeeded, but sync failed: ${syncResult.message}"
                    }
                }
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
        aiSettings.clear()
        _aiUrl.value = null
        _aiApiKey.value = null
        _aiModelId.value = null
        _statusMessage.value = "Configuration cleared"
    }

    fun clearStatus() {
        _statusMessage.value = null
    }
}
