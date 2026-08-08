package com.reflect.android.data

import com.specular.android.data.local.MarkdownAttachmentResolver
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MarkdownAttachmentResolverTest {
    @Test
    fun resolvesAttachmentsRelativeToNestedNote() {
        assertEquals(
            "attachments/image.png",
            MarkdownAttachmentResolver.resolve("notes/Meeting.md", "../attachments/image.png")
        )
    }

    @Test
    fun treatsAssetsAsRepositoryRootForReflectCompatibility() {
        assertEquals(
            "assets/pasted.png",
            MarkdownAttachmentResolver.resolve("notes/Imported.md", "assets/pasted.png")
        )
    }

    @Test
    fun createsCorrectRelativeReferenceForDailyAndRootNotes() {
        assertEquals(
            "../attachments/photo.jpg",
            MarkdownAttachmentResolver.referenceFor("daily/2026-08-08.md", "attachments/photo.jpg")
        )
        assertEquals(
            "attachments/photo.jpg",
            MarkdownAttachmentResolver.referenceFor("Root note.md", "attachments/photo.jpg")
        )
    }

    @Test
    fun ignoresExternalAndMetadataReferences() {
        assertNull(MarkdownAttachmentResolver.resolve("notes/Test.md", "https://example.com/a.png"))
        assertNull(MarkdownAttachmentResolver.resolve("notes/Test.md", "../assets/image.png.reflect.md"))
    }
}
