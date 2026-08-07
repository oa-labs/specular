package com.specular.android.data.remote

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AiSnippetGeneratorTest {
    @Test fun sendsRequestedPromptAndKeepsSnippetUnderSevenWords() = runTest {
        val generator = AiSnippetGenerator(object : AiProviderApi {
            override suspend fun complete(
                url: String,
                authorization: String,
                request: ChatCompletionRequest
            ): ChatCompletionResponse {
                assertEquals("https://provider.test/chat", url)
                assertEquals("Bearer key", authorization)
                assertEquals("model-id", request.model)
                assertEquals(AiSnippetGenerator.PROMPT + "\n\nNote content", request.messages.single().content)
                return ChatCompletionResponse(
                    choices = listOf(ChatChoice(ChatMessageResponse("one two three four five six seven")))
                )
            }
        })

        val snippet = generator.generate(
            AiProviderConfig("https://provider.test/chat", "key", "model-id"),
            "Note content"
        )

        assertEquals("one two three four five six", snippet)
        assertTrue(snippet.split(" ").size < 7)
    }
}
