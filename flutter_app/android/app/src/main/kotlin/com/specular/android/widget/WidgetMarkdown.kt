package com.specular.android.widget

import android.text.Html
import android.text.Spanned

/**
 * RemoteViews can carry Android framework spans but not Compose/Flutter views.
 * Convert the common inline Markdown forms after HTML-escaping user content.
 */
internal fun renderWidgetMarkdown(markdown: String): Spanned {
    val escaped = Html.escapeHtml(markdown)
        // Reflect's [[wikilinks]] are rendered as a link span, matching the
        // Flutter to-do list. The row itself remains the click target because
        // RemoteViews cannot attach a PendingIntent to an individual span.
        .replace(Regex("\\[\\[([^]\\r\\n]+)]]")) { match ->
            val title = match.groupValues[1].trim()
            if (title.isEmpty()) match.value else "<a href=\"specular-wiki\">$title</a>"
        }
        .replace(Regex("!\\[([^]]*)]\\([^)]*\\)"), "$1")
        .replace(Regex("\\[([^]]+)]\\([^)]*\\)"), "$1")
        .replace(Regex("`([^`]+)`"), "<tt>$1</tt>")
        .replace(Regex("\\*\\*([^*]+)\\*\\*|__([^_]+)__")) { match ->
            "<b>${match.groupValues[1].ifBlank { match.groupValues[2] }}</b>"
        }
        .replace(Regex("(?<!\\*)\\*([^*]+)\\*(?!\\*)|(?<!_)_([^_]+)_(?!_)")) { match ->
            "<i>${match.groupValues[1].ifBlank { match.groupValues[2] }}</i>"
        }
        .replace("\n", "<br>")
    return Html.fromHtml(escaped, Html.FROM_HTML_MODE_LEGACY)
}
