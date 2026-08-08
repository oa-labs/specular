package com.specular.android.data.remote

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

data class AiProviderConfig(
    val url: String,
    val apiKey: String,
    val modelId: String
)

enum class VoiceProvider(
    val label: String,
    val defaultEndpoint: String?
) {
    OPENROUTER("OpenRouter", "https://openrouter.ai/api/v1/audio/transcriptions"),
    OPENAI("OpenAI", "https://api.openai.com/v1/audio/transcriptions"),
    CUSTOM_OPENAI_COMPATIBLE("Custom OpenAI-compatible", null);

    companion object {
        fun fromStored(value: String?): VoiceProvider? = entries.firstOrNull { it.name == value }
    }
}

/** A transcription provider may reuse the encrypted key from note previews. */
data class VoiceTranscriptionConfig(
    val provider: VoiceProvider,
    val modelId: String,
    val usePreviewApiKey: Boolean,
    val endpoint: String = "",
    val apiKey: String = ""
)

data class ResolvedVoiceTranscriptionConfig(
    val provider: VoiceProvider,
    val endpoint: String,
    val apiKey: String,
    val modelId: String
)

/** Encrypted local configuration for an OpenAI-compatible chat-completions endpoint. */
@Singleton
class AiProviderSettings @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val masterKey by lazy {
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
    }

    private val prefs: SharedPreferences by lazy {
        EncryptedSharedPreferences.create(
            context,
            "secret_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private val _config = MutableStateFlow(readConfig())
    val config: StateFlow<AiProviderConfig?> = _config.asStateFlow()
    private val _voiceConfig = MutableStateFlow(readVoiceConfig())
    val voiceConfig: StateFlow<VoiceTranscriptionConfig?> = _voiceConfig.asStateFlow()

    fun save(url: String, apiKey: String, modelId: String) {
        prefs.edit()
            .putString(KEY_URL, url.trim())
            .putString(KEY_API_KEY, apiKey.trim())
            .putString(KEY_MODEL_ID, modelId.trim())
            .apply()
        _config.value = readConfig()
    }

    fun clear() {
        prefs.edit()
            .remove(KEY_URL)
            .remove(KEY_API_KEY)
            .remove(KEY_MODEL_ID)
            .remove(KEY_VOICE_PROVIDER)
            .remove(KEY_VOICE_MODEL_ID)
            .remove(KEY_VOICE_USE_PREVIEW_KEY)
            .remove(KEY_VOICE_ENDPOINT)
            .remove(KEY_VOICE_API_KEY)
            .apply()
        _config.value = null
        _voiceConfig.value = null
    }

    fun isConfigured(): Boolean = _config.value != null

    fun saveVoice(config: VoiceTranscriptionConfig?) {
        if (config == null || config.modelId.isBlank()) {
            clearVoice()
            return
        }
        prefs.edit()
            .putString(KEY_VOICE_PROVIDER, config.provider.name)
            .putString(KEY_VOICE_MODEL_ID, config.modelId.trim())
            .putBoolean(KEY_VOICE_USE_PREVIEW_KEY, config.usePreviewApiKey)
            .putString(KEY_VOICE_ENDPOINT, config.endpoint.trim())
            .putString(KEY_VOICE_API_KEY, config.apiKey.trim())
            .apply()
        _voiceConfig.value = readVoiceConfig()
    }

    fun clearVoice() {
        prefs.edit()
            .remove(KEY_VOICE_PROVIDER)
            .remove(KEY_VOICE_MODEL_ID)
            .remove(KEY_VOICE_USE_PREVIEW_KEY)
            .remove(KEY_VOICE_ENDPOINT)
            .remove(KEY_VOICE_API_KEY)
            .apply()
        _voiceConfig.value = null
    }

    fun resolvedVoiceConfig(): ResolvedVoiceTranscriptionConfig? {
        val voice = _voiceConfig.value ?: return null
        val endpoint = (voice.provider.defaultEndpoint ?: voice.endpoint).trim()
        val apiKey = if (voice.usePreviewApiKey) _config.value?.apiKey.orEmpty() else voice.apiKey
        return endpoint.takeIf { it.isNotBlank() }?.let { resolvedEndpoint ->
            apiKey.trim().takeIf { it.isNotBlank() }?.let { resolvedKey ->
                ResolvedVoiceTranscriptionConfig(
                    provider = voice.provider,
                    endpoint = resolvedEndpoint,
                    apiKey = resolvedKey,
                    modelId = voice.modelId
                )
            }
        }
    }

    fun isVoiceConfigured(): Boolean = resolvedVoiceConfig() != null

    private fun readConfig(): AiProviderConfig? {
        val url = prefs.getString(KEY_URL, null)?.trim().orEmpty()
        val apiKey = prefs.getString(KEY_API_KEY, null)?.trim().orEmpty()
        val modelId = prefs.getString(KEY_MODEL_ID, null)?.trim().orEmpty()
        return if (url.isNotEmpty() && apiKey.isNotEmpty() && modelId.isNotEmpty()) {
            AiProviderConfig(url, apiKey, modelId)
        } else {
            null
        }
    }

    private fun readVoiceConfig(): VoiceTranscriptionConfig? {
        val provider = VoiceProvider.fromStored(prefs.getString(KEY_VOICE_PROVIDER, null)) ?: return null
        val modelId = prefs.getString(KEY_VOICE_MODEL_ID, null)?.trim().orEmpty()
        val usePreviewApiKey = prefs.getBoolean(KEY_VOICE_USE_PREVIEW_KEY, true)
        val endpoint = prefs.getString(KEY_VOICE_ENDPOINT, null)?.trim().orEmpty()
        val apiKey = prefs.getString(KEY_VOICE_API_KEY, null)?.trim().orEmpty()
        return if (modelId.isNotEmpty()) {
            VoiceTranscriptionConfig(provider, modelId, usePreviewApiKey, endpoint, apiKey)
        } else {
            null
        }
    }

    private companion object {
        const val KEY_URL = "ai_provider_url"
        const val KEY_API_KEY = "ai_provider_api_key"
        const val KEY_MODEL_ID = "ai_provider_model_id"
        const val KEY_VOICE_PROVIDER = "voice_provider"
        const val KEY_VOICE_MODEL_ID = "voice_model_id"
        const val KEY_VOICE_USE_PREVIEW_KEY = "voice_use_preview_key"
        const val KEY_VOICE_ENDPOINT = "voice_endpoint"
        const val KEY_VOICE_API_KEY = "voice_api_key"
    }
}
