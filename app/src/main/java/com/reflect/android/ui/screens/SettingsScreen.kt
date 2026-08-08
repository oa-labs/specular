package com.specular.android.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.NavController
import com.specular.android.data.remote.GitHubAuth
import com.specular.android.data.remote.RepoResponse
import com.specular.android.data.remote.AiProviderSettings
import androidx.work.WorkManager
import com.specular.android.sync.SyncScheduler
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
    val statusIsError by vm.statusIsError.collectAsState()

    var tokenInput by remember(token) { mutableStateOf(token ?: "") }
    var ownerInput by remember(owner) { mutableStateOf(owner ?: "") }
    var repoInput by remember(repo) { mutableStateOf(repo ?: "") }
    var aiUrlInput by remember(aiUrl) { mutableStateOf(aiUrl ?: "") }
    var aiApiKeyInput by remember(aiApiKey) { mutableStateOf(aiApiKey ?: "") }
    var aiModelIdInput by remember(aiModelId) { mutableStateOf(aiModelId ?: "") }
    var showToken by remember { mutableStateOf(false) }
    var showAiApiKey by remember { mutableStateOf(false) }
    var showClearDialog by remember { mutableStateOf(false) }
    var showRepositoryPicker by remember { mutableStateOf(false) }
    val repositories by vm.repositories.collectAsState()
    val isLoadingRepositories by vm.isLoadingRepositories.collectAsState()
    val repositoryPickerError by vm.repositoryPickerError.collectAsState()

    val githubConfigured = vm.isConfigured()
    val aiConfigured = vm.isAiConfigured()
    val hasChanges = tokenInput != (token ?: "") ||
        ownerInput != (owner ?: "") ||
        repoInput != (repo ?: "") ||
        aiUrlInput != (aiUrl ?: "") ||
        aiApiKeyInput != (aiApiKey ?: "") ||
        aiModelIdInput != (aiModelId ?: "")

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
        bottomBar = {
            Surface(shadowElevation = 6.dp) {
                Button(
                    onClick = {
                        vm.save(tokenInput, ownerInput, repoInput, aiUrlInput, aiApiKeyInput, aiModelIdInput)
                    },
                    enabled = hasChanges && !isTesting,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .windowInsetsPadding(WindowInsets.navigationBars)
                ) {
                    Text(if (hasChanges) "Save changes" else "All changes saved")
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Control how Specular connects and creates note previews.", style = MaterialTheme.typography.bodyLarge)

            if (statusMessage != null) {
                StatusCard(statusMessage!!, statusIsError)
            }

            SettingsCard(
                icon = { Icon(Icons.Default.Cloud, contentDescription = null) },
                title = "GitHub sync",
                description = "Keep your markdown repository available offline.",
                configured = githubConfigured
            ) {
                OutlinedTextField(
                    value = tokenInput,
                    onValueChange = { tokenInput = it },
                    label = { Text("Personal access token") },
                    supportingText = { Text("Stored securely on this device") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = if (showToken) VisualTransformation.None else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { showToken = !showToken }) {
                            Icon(
                                if (showToken) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = if (showToken) "Hide token" else "Show token"
                            )
                        }
                    }
                )

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        value = ownerInput,
                        onValueChange = { ownerInput = it },
                        label = { Text("Owner") },
                        modifier = Modifier.weight(1f),
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = repoInput,
                        onValueChange = { repoInput = it },
                        label = { Text("Repository") },
                        modifier = Modifier.weight(1f),
                        singleLine = true
                    )
                }

                OutlinedButton(
                    onClick = {
                        showRepositoryPicker = true
                        vm.loadRepositories(tokenInput)
                    },
                    enabled = tokenInput.isNotBlank() && !isLoadingRepositories,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (isLoadingRepositories) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text("Choose repository")
                }
                Text(
                    "The picker verifies that the selected repository contains Markdown notes.",
                    style = MaterialTheme.typography.bodySmall
                )

                OutlinedButton(
                    onClick = { vm.testConnection() },
                    enabled = !isTesting && githubConfigured,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (isTesting) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text(if (isTesting) "Testing connection…" else "Test connection")
                }
            }

            SettingsCard(
                icon = { Icon(Icons.Default.AutoAwesome, contentDescription = null) },
                title = "AI note previews",
                description = "Generate a short subject phrase for notes without a snippet.",
                configured = aiConfigured
            ) {
                OutlinedTextField(
                    value = aiUrlInput,
                    onValueChange = { aiUrlInput = it },
                    label = { Text("Chat completions URL") },
                    placeholder = { Text("https://provider.example/v1/chat/completions") },
                    supportingText = { Text("OpenAI-compatible endpoint") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                OutlinedTextField(
                    value = aiApiKeyInput,
                    onValueChange = { aiApiKeyInput = it },
                    label = { Text("API key") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    visualTransformation = if (showAiApiKey) VisualTransformation.None else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { showAiApiKey = !showAiApiKey }) {
                            Icon(
                                if (showAiApiKey) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = if (showAiApiKey) "Hide API key" else "Show API key"
                            )
                        }
                    }
                )

                OutlinedTextField(
                    value = aiModelIdInput,
                    onValueChange = { aiModelIdInput = it },
                    label = { Text("Model ID") },
                    placeholder = { Text("your-model-name") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                InfoCallout("Only notes without a snippet are sent. Generated previews are saved into the note's markdown metadata.")
            }

            OutlinedCard(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.outlinedCardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
                        Spacer(Modifier.width(10.dp))
                        Text("Privacy and storage", style = MaterialTheme.typography.titleMedium)
                    }
                    Text(
                        "Credentials are stored securely. AI requests send note content to the provider URL you configure. Specular does not add telemetry.",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }

            TextButton(
                onClick = { showClearDialog = true },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
            ) {
                Icon(Icons.Default.DeleteOutline, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Clear all connection settings")
            }

            Text(
                "Build: gmsFree · no Play Services",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )

            Spacer(Modifier.height(8.dp))
        }
    }

    if (showClearDialog) {
        AlertDialog(
            onDismissRequest = { showClearDialog = false },
            icon = { Icon(Icons.Default.DeleteOutline, contentDescription = null) },
            title = { Text("Clear connection settings?") },
            text = { Text("This removes the GitHub and AI provider credentials stored on this device. Your local notes will remain.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        vm.clear()
                        showClearDialog = false
                        tokenInput = ""
                        ownerInput = ""
                        repoInput = ""
                        aiUrlInput = ""
                        aiApiKeyInput = ""
                        aiModelIdInput = ""
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) { Text("Clear settings") }
            },
            dismissButton = {
                TextButton(onClick = { showClearDialog = false }) { Text("Cancel") }
            }
        )
    }

    if (showRepositoryPicker) {
        AlertDialog(
            onDismissRequest = { if (!isLoadingRepositories) showRepositoryPicker = false },
            title = { Text("Choose a Reflect repository") },
            text = {
                when {
                    isLoadingRepositories -> Box(
                        modifier = Modifier.fillMaxWidth().height(160.dp),
                        contentAlignment = Alignment.Center
                    ) { CircularProgressIndicator() }
                    repositoryPickerError != null -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(repositoryPickerError!!, color = MaterialTheme.colorScheme.error)
                        OutlinedButton(onClick = { vm.loadRepositories(tokenInput) }) { Text("Try again") }
                    }
                    repositories.isEmpty() -> Text("No accessible repositories were found for this token.")
                    else -> LazyColumn(modifier = Modifier.heightIn(max = 360.dp)) {
                        items(repositories, key = { it.id }) { repository ->
                            ListItem(
                                headlineContent = { Text(repository.full_name) },
                                supportingContent = {
                                    Text(if (repository.private) "Private · ${repository.default_branch}" else "Public · ${repository.default_branch}")
                                },
                                modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp)
                            )
                            HorizontalDivider()
                            // The whole row remains readable while the action below is explicit.
                            TextButton(
                                onClick = {
                                    vm.selectRepository(tokenInput, repository) {
                                        showRepositoryPicker = false
                                    }
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) { Text("Use this repository") }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showRepositoryPicker = false }, enabled = !isLoadingRepositories) { Text("Cancel") }
            }
        )
    }
}

@Composable
private fun SettingsCard(
    icon: @Composable () -> Unit,
    title: String,
    description: String,
    configured: Boolean,
    content: @Composable ColumnScope.() -> Unit
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Surface(
                    modifier = Modifier.size(42.dp),
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primaryContainer
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onPrimaryContainer) {
                            icon()
                        }
                    }
                }
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleMedium)
                    Text(description, style = MaterialTheme.typography.bodySmall)
                }
                Spacer(Modifier.width(8.dp))
                StatusPill(configured)
            }
            content()
        }
    }
}

@Composable
private fun StatusPill(configured: Boolean) {
    val container = if (configured) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
    val content = if (configured) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
    Surface(shape = MaterialTheme.shapes.small, color = container) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (configured) {
                Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(14.dp), tint = content)
                Spacer(Modifier.width(4.dp))
            }
            Text(if (configured) "Ready" else "Not set", style = MaterialTheme.typography.labelSmall, color = content)
        }
    }
}

@Composable
private fun StatusCard(message: String, isError: Boolean) {
    val background = if (isError) MaterialTheme.colorScheme.errorContainer else MaterialTheme.colorScheme.primaryContainer
    val content = if (isError) MaterialTheme.colorScheme.onErrorContainer else MaterialTheme.colorScheme.onPrimaryContainer
    Card(
        colors = CardDefaults.cardColors(containerColor = background),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(if (isError) Icons.Default.Info else Icons.Default.CheckCircle, contentDescription = null, tint = content)
            Spacer(Modifier.width(10.dp))
            Text(message, style = MaterialTheme.typography.bodyMedium, color = content)
        }
    }
}

@Composable
private fun InfoCallout(message: String) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.Top) {
            Icon(Icons.Default.Info, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(message, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val auth: GitHubAuth,
    private val workManager: WorkManager,
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

    private val _statusIsError = MutableStateFlow(false)
    val statusIsError: StateFlow<Boolean> = _statusIsError.asStateFlow()

    private val _repositories = MutableStateFlow<List<RepoResponse>>(emptyList())
    val repositories: StateFlow<List<RepoResponse>> = _repositories.asStateFlow()
    private val _isLoadingRepositories = MutableStateFlow(false)
    val isLoadingRepositories: StateFlow<Boolean> = _isLoadingRepositories.asStateFlow()
    private val _repositoryPickerError = MutableStateFlow<String?>(null)
    val repositoryPickerError: StateFlow<String?> = _repositoryPickerError.asStateFlow()

    fun isConfigured(): Boolean = auth.isConfigured()

    fun isAiConfigured(): Boolean = aiSettings.isConfigured()

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
        val aiFields = listOf(aiUrlInput, aiApiKeyInput, aiModelIdInput)
        val aiIsComplete = aiFields.all { it.isNotBlank() }
        val aiIsEmpty = aiFields.all { it.isBlank() }
        if (aiIsEmpty) {
            aiSettings.clear()
        } else if (aiIsComplete) {
            aiSettings.save(aiUrlInput, aiApiKeyInput, aiModelIdInput)
        }

        _token.value = auth.token
        _owner.value = auth.repoOwner
        _repo.value = auth.repoName
        // Keep incomplete AI values in the form as a draft instead of silently wiping them.
        if (aiIsComplete || aiIsEmpty) {
            _aiUrl.value = aiSettings.config.value?.url
            _aiApiKey.value = aiSettings.config.value?.apiKey
            _aiModelId.value = aiSettings.config.value?.modelId
        }

        if (auth.isConfigured()) {
            SyncScheduler.schedulePeriodic(workManager)
            SyncScheduler.enqueueInitialSync(workManager)
        }

        val aiFieldsEntered = aiFields.count { it.isNotBlank() }
        _statusIsError.value = !auth.isConfigured() && !aiSettings.isConfigured() || aiFieldsEntered in 1..2
        _statusMessage.value = when {
            auth.isConfigured() && aiFieldsEntered in 1..2 -> "GitHub settings saved and notes are syncing. Complete all AI fields to enable previews."
            auth.isConfigured() && aiSettings.isConfigured() -> "Changes saved. Notes are syncing in the background."
            auth.isConfigured() -> "GitHub settings saved. Notes are syncing in the background."
            aiSettings.isConfigured() -> "AI provider saved. Add GitHub details if you want sync."
            aiFieldsEntered in 1..2 -> "Complete all AI fields to enable note previews."
            else -> "Add a GitHub token, owner, and repository to enable sync."
        }
    }

    fun testConnection() {
        viewModelScope.launch {
            _isTesting.value = true
            _statusIsError.value = false
            _statusMessage.value = "Testing connection to GitHub..."

            try {
                val result = auth.testConnection()
                _statusMessage.value = "$result. Notes are syncing in the background."
            } catch (e: Exception) {
                val message = when (e) {
                    is IllegalArgumentException -> e.message ?: "Invalid configuration"
                    is IllegalStateException -> e.message ?: "Configuration error"
                    else -> "Connection failed: ${e.message}"
                }
                _statusIsError.value = true
                _statusMessage.value = message
            } finally {
                _isTesting.value = false
            }
        }
    }

    fun loadRepositories(tokenInput: String) {
        viewModelScope.launch {
            _isLoadingRepositories.value = true
            _repositoryPickerError.value = null
            try {
                _repositories.value = auth.listRepositories(tokenInput)
            } catch (e: Exception) {
                _repositories.value = emptyList()
                _repositoryPickerError.value = e.message ?: "Could not load repositories."
            } finally {
                _isLoadingRepositories.value = false
            }
        }
    }

    fun selectRepository(tokenInput: String, repository: RepoResponse, onValidated: () -> Unit) {
        viewModelScope.launch {
            _isLoadingRepositories.value = true
            _repositoryPickerError.value = null
            try {
                auth.validateReflectRepository(tokenInput, repository)
                _owner.value = repository.owner.login
                _repo.value = repository.name
                _statusIsError.value = false
                _statusMessage.value = "${repository.full_name} is a valid Markdown notes repository. Save changes to connect it."
                onValidated()
            } catch (e: Exception) {
                _repositoryPickerError.value = e.message ?: "This repository could not be validated."
            } finally {
                _isLoadingRepositories.value = false
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
        _statusIsError.value = false
        _statusMessage.value = "Configuration cleared"
    }

    fun clearStatus() {
        _statusMessage.value = null
    }
}
