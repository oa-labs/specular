package com.specular.android.data.remote

import com.squareup.moshi.Json
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Url

interface AiProviderApi {
    @POST
    suspend fun complete(
        @Url url: String,
        @Header("Authorization") authorization: String,
        @Body request: ChatCompletionRequest
    ): ChatCompletionResponse
}

data class ChatCompletionRequest(
    val model: String,
    val messages: List<ChatMessage>,
    val temperature: Double = 0.2
)

data class ChatMessage(
    val role: String,
    val content: String
)

data class ChatCompletionResponse(
    val choices: List<ChatChoice> = emptyList()
)

data class ChatChoice(
    val message: ChatMessageResponse
)

data class ChatMessageResponse(
    @Json(name = "content") val content: String?
)
