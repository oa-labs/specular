package com.reflect.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = ReflectAccent,
    onPrimary = ReflectOnAccent,
    primaryContainer = ReflectAccentDark,
    secondary = ReflectNeutral,
    onSecondary = ReflectOnNeutral,
    surface = ReflectSurface,
    onSurface = ReflectNeutral,
    surfaceVariant = ReflectSurfaceVariant,
    error = ReflectError
)

private val DarkColors = darkColorScheme(
    primary = ReflectAccent,
    onPrimary = ReflectOnAccent,
    primaryContainer = ReflectAccentDark,
    secondary = ReflectNeutral,
    surface = ReflectNeutral,
    onSurface = ReflectSurface,
    error = ReflectError
)

@Composable
fun ReflectTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    val colors = if (darkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = colors,
        content = content
    )
}
