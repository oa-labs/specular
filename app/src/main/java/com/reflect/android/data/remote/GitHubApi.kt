package com.specular.android.data.remote

import retrofit2.http.*
import com.specular.android.data.remote.PutContentRequest

/**
 * GitHub REST + Git Data API for file-per-note sync.
 * No GMS dependency. Auth via OAuth token header.
 */
interface GitHubApi {

    // ---- Contents API (single-file) ----
    @GET("repos/{owner}/{repo}/contents/{path}")
    suspend fun getContent(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Path(value = "path", encoded = true) path: String,
        @Header("Authorization") auth: String,
        @Query("ref") ref: String = "main"
    ): ContentResponse

    @PUT("repos/{owner}/{repo}/contents/{path}")
    suspend fun putContent(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Path(value = "path", encoded = true) path: String,
        @Header("Authorization") auth: String,
        @Body body: PutContentRequest
    ): PutContentResponse

    // GitHub's Contents delete endpoint requires the target SHA in a JSON body.
    // Retrofit's @DELETE annotation disallows bodies, so use @HTTP explicitly.
    @HTTP(method = "DELETE", path = "repos/{owner}/{repo}/contents/{path}", hasBody = true)
    suspend fun deleteContent(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Path(value = "path", encoded = true) path: String,
        @Header("Authorization") auth: String,
        @Body body: DeleteContentRequest
    ): PutContentResponse

    // ---- Git Data API (tree / commits for initial + batch) ----
    @GET("repos/{owner}/{repo}/git/trees/{sha}")
    suspend fun getTree(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Path("sha") sha: String,
        @Header("Authorization") auth: String,
        @Query("recursive") recursive: Int = 1
    ): TreeResponse

    @GET("repos/{owner}/{repo}/git/blobs/{sha}")
    suspend fun getBlob(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Path("sha") sha: String,
        @Header("Authorization") auth: String
    ): BlobResponse

    @GET("repos/{owner}/{repo}/git/ref/heads/{branch}")
    suspend fun getRef(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Path("branch") branch: String,
        @Header("Authorization") auth: String
    ): RefResponse

    @GET("repos/{owner}/{repo}")
    suspend fun getRepo(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
        @Header("Authorization") auth: String
    ): RepoResponse

    @GET("user/repos")
    suspend fun listRepos(
        @Header("Authorization") auth: String,
        @Query("per_page") perPage: Int = 100,
        @Query("sort") sort: String = "updated"
    ): List<RepoResponse>
}

// ---- DTOs ----

data class ContentResponse(
    val name: String,
    val path: String,
    val sha: String,
    val content: String?, // base64
    val encoding: String?,
    val type: String
)

data class PutContentRequest(
    val message: String,
    val content: String, // base64
    val sha: String? = null,
    val branch: String = "main"
)

data class DeleteContentRequest(
    val message: String,
    val sha: String,
    val branch: String = "main"
)

data class PutContentResponse(
    val content: ContentResponse?,
    val commit: CommitBrief?
)

data class CommitBrief(val sha: String, val message: String)

data class TreeResponse(
    val sha: String,
    val tree: List<TreeEntry>,
    val truncated: Boolean
)

data class TreeEntry(
    val path: String,
    val mode: String,
    val type: String, // blob, tree
    val sha: String,
    val size: Int? = null
)

data class BlobResponse(
    val sha: String,
    val content: String,
    val encoding: String,
    val size: Int
)

data class RefResponse(
    val ref: String,
    val `object`: RefObject
)

data class RefObject(val sha: String, val type: String)

data class RepoResponse(
    val id: Long,
    val name: String,
    val full_name: String,
    val `private`: Boolean,
    val default_branch: String,
    val owner: Owner
)

data class Owner(val login: String)
