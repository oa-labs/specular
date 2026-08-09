package com.specular.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = SpecularAccent,
    onPrimary = SpecularOnAccent,
    primaryContainer = SpecularAccentDark,
    secondary = SpecularNeutral,
    onSecondary = SpecularOnNeutral,
    background = SpecularSurface,
    onBackground = SpecularNeutral,
    surface = SpecularSurface,
    onSurface = SpecularNeutral,
    surfaceVariant = SpecularSurfaceVariant,
    error = SpecularError
)

private val DarkColors = darkColorScheme(
    primary = SpecularAccent,
    onPrimary = SpecularOnAccent,
    primaryContainer = SpecularAccentDark,
    secondary = SpecularNeutral,
    background = SpecularNeutral,
    onBackground = SpecularSurface,
    surface = SpecularNeutral,
    onSurface = SpecularSurface,
    error = SpecularError
)

@Composable
fun SpecularTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    val colors = if (darkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = colors,
        content = content
    )
}
