package com.specular.android.data.remote

import com.squareup.moshi.Moshi
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import java.io.File

class VoiceTranscriberTest {
    @Test fun `OpenRouter transcription sends base64 JSON`() = runTest {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("{\"text\":\"Quick thought\"}"))
            val transcriber = VoiceTranscriber(OkHttpClient(), Moshi.Builder().build(), mock(AiProviderSettings::class.java))
            val audio = audioFile()

            val transcript = transcriber.transcribe(
                ResolvedVoiceTranscriptionConfig(
                    VoiceProvider.OPENROUTER,
                    server.url("audio/transcriptions").toString(),
                    "openrouter-key",
                    "openai/whisper-large-v3"
                ),
                audio
            )

            assertEquals("Quick thought", transcript)
            val request = server.takeRequest()
            assertEquals("Bearer openrouter-key", request.getHeader("Authorization"))
            val body = request.body.readUtf8()
            assertTrue(body.contains("\"input_audio\""))
            assertTrue(body.contains("\"openai/whisper-large-v3\""))
            audio.delete()
        }
    }

    @Test fun `OpenAI-compatible transcription sends multipart audio`() = runTest {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("{\"text\":\"Buy milk\"}"))
            val transcriber = VoiceTranscriber(OkHttpClient(), Moshi.Builder().build(), mock(AiProviderSettings::class.java))
            val audio = audioFile()

            val transcript = transcriber.transcribe(
                ResolvedVoiceTranscriptionConfig(
                    VoiceProvider.OPENAI,
                    server.url("audio/transcriptions").toString(),
                    "openai-key",
                    "whisper-1"
                ),
                audio
            )

            assertEquals("Buy milk", transcript)
            val request = server.takeRequest()
            assertEquals("Bearer openai-key", request.getHeader("Authorization"))
            assertTrue(request.getHeader("Content-Type").orEmpty().startsWith("multipart/form-data"))
            val body = request.body.readUtf8()
            assertTrue(body.contains("name=\"model\""))
            assertTrue(body.contains("whisper-1"))
            assertTrue(body.contains("name=\"file\""))
            audio.delete()
        }
    }

    private fun audioFile(): File = File.createTempFile("specular-voice", ".m4a").apply {
        writeBytes(byteArrayOf(1, 2, 3, 4))
    }
}
