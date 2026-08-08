package com.specular.android.data.remote

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.specular.android.data.remote.GitHubApi
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import retrofit2.HttpException
import java.io.IOException

/**
 * Stores GitHub token in EncryptedSharedPreferences (excluded from backup).
 * Supports OAuth token + PAT fallback. See docs/reflect-contract.md.
 */
@Singleton
class GitHubAuth @Inject constructor(
    @ApplicationContext private val context: Context,
    private val api: GitHubApi
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

    /**
     * Tests whether the current token + repo combination works.
     * Returns success message or throws descriptive exception.
     */
    suspend fun testConnection(): String {
        val header = authHeader() ?: throw IllegalStateException("No token configured")
        val owner = repoOwner ?: throw IllegalStateException("No repo owner configured")
        val repo = repoName ?: throw IllegalStateException("No repo name configured")

        try {
            val repoInfo = api.getRepo(owner, repo, header)
            return "Successfully connected to ${repoInfo.full_name} (${if (repoInfo.private) "private" else "public"})"
        } catch (e: HttpException) {
            when (e.code()) {
                401 -> throw IllegalArgumentException("Invalid or expired token. Please check your PAT.")
                403 -> throw IllegalArgumentException("Permission denied. Make sure your PAT has 'Contents: read & write' scope.")
                404 -> throw IllegalArgumentException("Repository not found. Check owner and repo name.")
                else -> throw IllegalArgumentException("GitHub API error (${e.code()}): ${e.message()}")
            }
        } catch (e: IOException) {
            throw IllegalStateException("Network error. Please check your internet connection.")
        } catch (e: Exception) {
            throw IllegalStateException("Test failed: ${e.message ?: e.toString()}")
        }
    }

    /**
     * Lists repositories available to an entered PAT before it is saved. This keeps
     * connection setup from relying on error-prone owner/repository typing.
     */
    suspend fun listRepositories(candidateToken: String): List<RepoResponse> {
        require(candidateToken.isNotBlank()) { "Enter a personal access token first." }
        return try {
            api.listRepos("Bearer $candidateToken")
        } catch (e: HttpException) {
            when (e.code()) {
                401 -> throw IllegalArgumentException("Invalid or expired token. Please check your PAT.")
                403 -> throw IllegalArgumentException("GitHub denied repository access. Check your PAT permissions.")
                else -> throw IllegalArgumentException("GitHub API error (${e.code()}): ${e.message()}")
            }
        } catch (e: IOException) {
            throw IllegalStateException("Network error. Please check your internet connection.")
        }
    }

    /** Verifies that a selected repository looks like a usable Reflect notes repo. */
    suspend fun validateReflectRepository(candidateToken: String, repository: RepoResponse) {
        require(candidateToken.isNotBlank()) { "Enter a personal access token first." }
        try {
            val header = "Bearer $candidateToken"
            val ref = api.getRef(repository.owner.login, repository.name, repository.default_branch, header)
            val tree = api.getTree(repository.owner.login, repository.name, ref.`object`.sha, header)
            val containsMarkdown = tree.tree.any { entry ->
                entry.type == "blob" && entry.path.endsWith(".md") && !entry.path.endsWith(".reflect.md")
            }
            require(containsMarkdown) {
                "${repository.full_name} has no Markdown notes on ${repository.default_branch}."
            }
        } catch (e: HttpException) {
            when (e.code()) {
                401 -> throw IllegalArgumentException("Invalid or expired token. Please check your PAT.")
                403 -> throw IllegalArgumentException("Token cannot read ${repository.full_name}.")
                404 -> throw IllegalArgumentException("Repository or default branch was not found.")
                else -> throw IllegalArgumentException("GitHub API error (${e.code()}): ${e.message()}")
            }
        } catch (e: IOException) {
            throw IllegalStateException("Network error. Please check your internet connection.")
        }
    }

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
