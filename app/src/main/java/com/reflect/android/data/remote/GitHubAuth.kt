package com.specular.android.data.remote

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Stores GitHub token in EncryptedSharedPreferences (excluded from backup).
 * Supports OAuth token + PAT fallback. See docs/reflect-contract.md.
 */
@Singleton
class GitHubAuth @Inject constructor(
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

    var token: String?
        get() = prefs.getString("github_token", null)
        set(value) {
            if (value == null) prefs.edit().remove("github_token").apply()
            else prefs.edit().putString("github_token", value).apply()
        }

    var repoOwner: String?
        get() = prefs.getString("repo_owner", null)
        set(v) = prefs.edit().putString("repo_owner", v).apply()

    var repoName: String?
        get() = prefs.getString("repo_name", null)
        set(v) = prefs.edit().putString("repo_name", v).apply()

    fun authHeader(): String? = token?.let { "Bearer $it" }

    fun isConfigured(): Boolean = token != null && repoOwner != null && repoName != null

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        // OAuth constants — fill with your GitHub OAuth App credentials
        const val OAUTH_CLIENT_ID = "REPLACE_WITH_CLIENT_ID"
        const val OAUTH_REDIRECT_URI = "reflect://oauth"
        const val OAUTH_SCOPE = "repo"
        const val OAUTH_AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
        const val OAUTH_TOKEN_URL = "https://github.com/login/oauth/access_token"
    }
}
