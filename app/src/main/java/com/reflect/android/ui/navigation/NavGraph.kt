package com.specular.android.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.specular.android.ui.screens.NoteListScreen
import com.specular.android.ui.screens.NoteDetailScreen
import com.specular.android.ui.screens.EditorScreen
import com.specular.android.ui.screens.SearchScreen
import com.specular.android.ui.screens.SettingsScreen
import com.specular.android.ui.screens.OnboardingScreen

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
fun SpecularNavGraph(
    navController: NavHostController,
    startDestination: String = Screen.List.route
) {
    NavHost(navController = navController, startDestination = startDestination) {
        composable(Screen.List.route) { NoteListScreen(navController) }
        composable(Screen.Search.route) { SearchScreen(navController) }
        composable(Screen.Detail.route) { backStack ->
            val id = backStack.arguments?.getString("id") ?: return@composable
            NoteDetailScreen(navController, id)
        }
        composable(Screen.Editor.route) { backStack ->
            val id = backStack.arguments?.getString("id") ?: return@composable
            EditorScreen(navController, id)
        }
        composable(Screen.Settings.route) { SettingsScreen(navController) }
        composable(Screen.Onboarding.route) { OnboardingScreen(navController) }
    }
}
