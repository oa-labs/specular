package com.specular.android.widget

import android.text.Html
import android.text.Spanned

/**
 * RemoteViews can carry Android framework spans but not Compose/Flutter views.
 * Convert the common inline Markdown forms after HTML-escaping user content.
 */
internal fun renderWidgetMarkdown(markdown: String): Spanned {
    val escaped = Html.escapeHtml(markdown)
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
