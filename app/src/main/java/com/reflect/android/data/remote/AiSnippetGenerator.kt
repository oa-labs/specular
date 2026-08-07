package com.specular.android.data.remote

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AiSnippetGenerator @Inject constructor(
    private val api: AiProviderApi
) {
    suspend fun generate(config: AiProviderConfig, content: String): String = withContext(Dispatchers.IO) {
        val response = api.complete(
            url = config.url,
            authorization = "Bearer ${config.apiKey}",
            request = ChatCompletionRequest(
                model = config.modelId,
                messages = listOf(
                    ChatMessage("user", PROMPT + "\n\n" + content)
                )
            )
        )
        val result = response.choices.firstOrNull()?.message?.content
            ?.replace(Regex("\\s+"), " ")
            ?.trim()
            ?.removePrefix("\"")
            ?.removeSuffix("\"")
            ?.takeIf { it.isNotBlank() }
            ?: error("AI provider returned no snippet")

        // Keep persisted metadata single-line and enforce the prompt's under-seven-word contract.
        result.split(" ").take(MAX_WORDS).joinToString(" ").trim()
    }

    companion object {
        const val PROMPT = "Provide a high-level phrase (under 7 words) summarizing the core subject of the content below for a UI list preview. Do not include specific data points (such as emails, dates, or phone numbers) and do not reference the note itself, note tags or the note type."
        private const val MAX_WORDS = 6
    }
}
