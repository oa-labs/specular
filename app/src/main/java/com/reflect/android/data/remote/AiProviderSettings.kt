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
            .apply()
        _config.value = null
    }

    fun isConfigured(): Boolean = _config.value != null

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

    private companion object {
        const val KEY_URL = "ai_provider_url"
        const val KEY_API_KEY = "ai_provider_api_key"
        const val KEY_MODEL_ID = "ai_provider_model_id"
    }
}
