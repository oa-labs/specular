package com.specular.android.data.remote

import com.squareup.moshi.JsonClass
import com.squareup.moshi.Moshi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.ByteString.Companion.toByteString
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/** Uploads a completed recording using the request format required by its provider. */
@Singleton
class VoiceTranscriber @Inject constructor(
    private val client: OkHttpClient,
    private val moshi: Moshi,
    private val settings: AiProviderSettings
) {
    suspend fun transcribe(audio: File): String {
        val config = settings.resolvedVoiceConfig()
            ?: error("Configure a voice transcription provider in Settings")
        return transcribe(config, audio)
    }

    internal suspend fun transcribe(config: ResolvedVoiceTranscriptionConfig, audio: File): String =
        withContext(Dispatchers.IO) {
            val request = when (config.provider) {
                VoiceProvider.OPENROUTER -> openRouterRequest(config, audio)
                VoiceProvider.OPENAI, VoiceProvider.CUSTOM_OPENAI_COMPATIBLE -> openAiCompatibleRequest(config, audio)
            }
            client.newCall(request).execute().use { response ->
                val payload = response.body?.string().orEmpty()
                if (!response.isSuccessful) {
                    error("Transcription failed (${response.code}): ${payload.take(200)}")
                }
                moshi.adapter(TranscriptionResponse::class.java).fromJson(payload)?.text
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: error("The transcription provider returned no text")
            }
        }

    private fun openRouterRequest(config: ResolvedVoiceTranscriptionConfig, audio: File): Request {
        val payload = OpenRouterTranscriptionRequest(
            inputAudio = OpenRouterAudioInput(
                data = audio.readBytes().toByteString().base64(),
                format = "m4a"
            ),
            model = config.modelId
        )
        val body = moshi.adapter(OpenRouterTranscriptionRequest::class.java).toJson(payload)
            .toRequestBody(JSON)
        return Request.Builder()
            .url(config.endpoint)
            .header("Authorization", "Bearer ${config.apiKey}")
            .post(body)
            .build()
    }

    private fun openAiCompatibleRequest(config: ResolvedVoiceTranscriptionConfig, audio: File): Request {
        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("model", config.modelId)
            .addFormDataPart("file", audio.name, audio.asRequestBody(AUDIO_M4A))
            .build()
        return Request.Builder()
            .url(config.endpoint)
            .header("Authorization", "Bearer ${config.apiKey}")
            .post(body)
            .build()
    }

    private companion object {
        val JSON = "application/json; charset=utf-8".toMediaType()
        val AUDIO_M4A = "audio/mp4".toMediaType()
    }
}

@JsonClass(generateAdapter = true)
internal data class OpenRouterTranscriptionRequest(
    @com.squareup.moshi.Json(name = "input_audio") val inputAudio: OpenRouterAudioInput,
    val model: String
)

@JsonClass(generateAdapter = true)
internal data class OpenRouterAudioInput(
    val data: String,
    val format: String
)

@JsonClass(generateAdapter = true)
internal data class TranscriptionResponse(val text: String?)
