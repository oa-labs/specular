package com.reflect.android.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable

sealed class Screen(val route: String) {
    data object List : Screen("list")
    data object Search : Screen("search")
    data object Detail : Screen("detail/{id}") {
        fun routeFor(id: String) = "detail/$id"
    }
    data object Editor : Screen("editor/{id}") {
        fun routeFor(id: String) = "editor/$id"
        fun routeForNew() = "editor/__new__"
    }
    data object Settings : Screen("settings")
    data object Onboarding : Screen("onboarding")
}

@Composable
fun ReflectNavGraph(navController: NavHostController) {
    NavHost(navController = navController, startDestination = Screen.List.route) {
        composable(Screen.List.route) { com.reflect.android.ui.screens.NoteListScreen(navController) }
        composable(Screen.Search.route) { com.reflect.android.ui.screens.SearchScreen(navController) }
        composable(Screen.Detail.route) { backStack ->
            val id = backStack.arguments?.getString("id") ?: return@composable
            com.reflect.android.ui.screens.NoteDetailScreen(navController, id)
        }
        composable(Screen.Editor.route) { backStack ->
            val id = backStack.arguments?.getString("id") ?: return@composable
            com.reflect.android.ui.screens.EditorScreen(navController, id)
        }
        composable(Screen.Settings.route) { com.reflect.android.ui.screens.SettingsScreen(navController) }
        composable(Screen.Onboarding.route) { com.reflect.android.ui.screens.OnboardingScreen(navController) }
    }
}
