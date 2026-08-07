package com.specular.android.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.specular.android.ui.navigation.Screen
import com.specular.android.ui.navigation.SpecularNavGraph
import com.specular.android.ui.theme.SpecularTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private companion object {
        const val NAVIGATION_PREFS = "navigation"
        const val LAST_OPENED_NOTE_ID = "last_opened_note_id"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
                        startDestination = lastOpenedNoteId?.let(Screen.Detail::routeFor) ?: Screen.List.route
                    )
                }
            }
        }
    }
}
