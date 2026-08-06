package com.reflect.android.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.reflect.android.ui.navigation.Screen

@Composable
fun OnboardingScreen(navController: NavController) {
    Column(modifier = Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Welcome to Reflect for Android", style = MaterialTheme.typography.headlineSmall)
        Text("Local markdown, GitHub-backed. Your files stay yours.", style = MaterialTheme.typography.bodyMedium)
        Text("1. On your Mac, enable Settings → Backup → GitHub and pick a repo.\n2. On Android, open Settings and paste a PAT (or complete OAuth) plus owner/repo.\n3. Sync — your notes appear.", style = MaterialTheme.typography.bodySmall)
        Button(onClick = { navController.navigate(Screen.Settings.route) }, modifier = Modifier.fillMaxWidth()) { Text("Go to Settings") }
        OutlinedButton(onClick = { navController.navigate(Screen.List.route) { popUpTo(Screen.Onboarding.route) { inclusive = true } } }, modifier = Modifier.fillMaxWidth()) { Text("Continue offline") }
    }
}
