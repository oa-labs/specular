package com.specular.android.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.view.WindowCompat
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.specular.android.ui.navigation.Screen
import com.specular.android.ui.navigation.SpecularNavGraph
import com.specular.android.ui.theme.SpecularTheme
import com.specular.android.widget.TodoWidgetProvider
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private companion object {
        const val NAVIGATION_PREFS = "navigation"
        const val LAST_OPENED_NOTE_ID = "last_opened_note_id"
    }

    private var widgetNavigation by mutableStateOf<WidgetNavigation?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        widgetNavigation = navigationFor(intent)
        setContent {
            SpecularTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    val context = LocalContext.current
                    val preferences = remember {
                        context.getSharedPreferences(NAVIGATION_PREFS, MODE_PRIVATE)
                    }
                    val lastOpenedNoteId = remember {
                        preferences.getString(LAST_OPENED_NOTE_ID, null)
                    }
                    val navController = rememberNavController()
                    val currentBackStackEntry = navController.currentBackStackEntryAsState().value
                    // Do not restore a previously open note over a widget tap.
                    val shouldRestoreLastOpenedNote = remember { widgetNavigation == null }

                    LaunchedEffect(currentBackStackEntry) {
                        val entry = currentBackStackEntry ?: return@LaunchedEffect
                        val noteId = when (entry.destination.route) {
                            Screen.Detail.route, Screen.Editor.route ->
                                entry.arguments?.getString("id")?.takeUnless { it == "__new__" }
                            else -> null
                        }
                        preferences.edit().apply {
                            if (noteId == null) remove(LAST_OPENED_NOTE_ID)
                            else putString(LAST_OPENED_NOTE_ID, noteId)
                        }.apply()
                    }

                    SpecularNavGraph(
                        navController = navController,
                        startDestination = Screen.List.route
                    )

                    LaunchedEffect(widgetNavigation) {
                        when (val request = widgetNavigation) {
                            is WidgetNavigation.Note -> navController.navigate(Screen.Detail.routeFor(request.noteId)) {
                                launchSingleTop = true
                            }
                            WidgetNavigation.NewTodo -> navController.navigate(Screen.Editor.routeForNewTodo()) {
                                launchSingleTop = true
                            }
                            WidgetNavigation.Todos -> navController.navigate(Screen.Todos.route) {
                                launchSingleTop = true
                            }
                            null -> Unit
                        }
                        if (widgetNavigation != null) widgetNavigation = null
                    }

                    // Keep the list beneath a restored note so the system back gesture
                    // returns home instead of finishing the activity immediately.
                    LaunchedEffect(lastOpenedNoteId, shouldRestoreLastOpenedNote) {
                        if (shouldRestoreLastOpenedNote) lastOpenedNoteId?.let { noteId ->
                            navController.navigate(Screen.Detail.routeFor(noteId))
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        widgetNavigation = navigationFor(intent)
    }

    private fun navigationFor(intent: android.content.Intent?): WidgetNavigation? = when (intent?.action) {
        TodoWidgetProvider.ACTION_OPEN_NOTE ->
            intent.getStringExtra(TodoWidgetProvider.EXTRA_NOTE_ID)?.let(WidgetNavigation::Note)
        TodoWidgetProvider.ACTION_NEW_TODO -> WidgetNavigation.NewTodo
        TodoWidgetProvider.ACTION_OPEN_TODOS -> WidgetNavigation.Todos
        else -> null
    }
}

private sealed interface WidgetNavigation {
    data class Note(val noteId: String) : WidgetNavigation
    data object NewTodo : WidgetNavigation
    data object Todos : WidgetNavigation
}
