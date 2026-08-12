package com.specular.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.StatFs
import com.specular.android.voice.VoiceRecordingService
import com.specular.android.widget.TodoWidgetRenderer
import com.specular.android.widget.TodoWidgetProvider

/**
 * Intentionally small Android boundary for the Flutter rewrite.
 *
 * The original Compose application stored the canonical Markdown mirror and its
 * Room database in this package's private directory.  Keeping the package name
 * lets Flutter open those exact paths after an ordinary app-store upgrade.
 */
class MainActivity : FlutterActivity() {
    private var widgetChannel: MethodChannel? = null
    private var pendingDocumentResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readLegacyState" -> result.success(readLegacyState())
                    "markLegacyMigrationComplete" -> {
                        getSharedPreferences(MIGRATION_PREFS, Context.MODE_PRIVATE)
                            .edit().putBoolean(MIGRATION_COMPLETE, true).apply()
                        result.success(null)
                    }
                    "availableBytes" -> result.success(StatFs(filesDir.absolutePath).availableBytes)
                    "startForegroundRecording" -> {
                        VoiceRecordingService.start(this)
                        result.success(null)
                    }
                    "stopForegroundRecording" -> {
                        VoiceRecordingService.stop(this)
                        result.success(null)
                    }
                    "foregroundStopRequested" -> result.success(VoiceRecordingService.stopRequested(this))
                    else -> result.notImplemented()
                }
            }
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "refreshTodoWidget") {
                    TodoWidgetRenderer.requestUpdate(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOCUMENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createBackupDocument" -> openDocumentCreator(
                        call.argument<String>("name") ?: "specular-backup.zip", result)
                    "openBackupDocument" -> openDocumentPicker(result)
                    "writeDocument" -> copyToDocument(
                        call.argument<String>("uri"), call.argument<String>("sourcePath"), result)
                    "readDocument" -> copyFromDocument(
                        call.argument<String>("uri"), call.argument<String>("destinationPath"), result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun getInitialRoute(): String? = routeFor(intent)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = routeFor(intent) ?: return
        widgetChannel?.invokeMethod("navigate", mapOf("route" to route))
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CREATE_DOCUMENT_REQUEST && requestCode != OPEN_DOCUMENT_REQUEST) return
        val result = pendingDocumentResult ?: return
        pendingDocumentResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri, data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
            result.success(uri.toString())
        } catch (_: Exception) {
            // A provider is allowed not to support persistent permissions; the
            // URI still remains valid for this immediate export/import.
            result.success(uri.toString())
        }
    }

    private fun openDocumentCreator(name: String, result: MethodChannel.Result) {
        if (pendingDocumentResult != null) {
            result.error("busy", "Another document picker is open.", null)
            return
        }
        pendingDocumentResult = result
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            putExtra(Intent.EXTRA_TITLE, name)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }, CREATE_DOCUMENT_REQUEST)
    }

    private fun openDocumentPicker(result: MethodChannel.Result) {
        if (pendingDocumentResult != null) {
            result.error("busy", "Another document picker is open.", null)
            return
        }
        pendingDocumentResult = result
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/zip"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }, OPEN_DOCUMENT_REQUEST)
    }

    private fun copyToDocument(uriValue: String?, sourcePath: String?, result: MethodChannel.Result) = try {
        if (uriValue == null || sourcePath == null) throw IllegalArgumentException("Missing backup file.")
        java.io.File(sourcePath).inputStream().use { input ->
            contentResolver.openOutputStream(Uri.parse(uriValue))!!.use { output -> input.copyTo(output) }
        }
        result.success(null)
    } catch (error: Exception) {
        result.error("write_failed", error.message, null)
    }

    private fun copyFromDocument(uriValue: String?, destinationPath: String?, result: MethodChannel.Result) = try {
        if (uriValue == null || destinationPath == null) throw IllegalArgumentException("Missing backup file.")
        val destination = java.io.File(destinationPath)
        destination.parentFile?.mkdirs()
        contentResolver.openInputStream(Uri.parse(uriValue))!!.use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        }
        result.success(null)
    } catch (error: Exception) {
        result.error("read_failed", error.message, null)
    }

    private fun routeFor(intent: Intent): String? = when (intent.action) {
        TodoWidgetProvider.ACTION_OPEN_NOTE -> intent.getStringExtra(TodoWidgetProvider.EXTRA_NOTE_ID)?.let { "/note/$it" }
        TodoWidgetProvider.ACTION_OPEN_TODOS -> "/todos"
        TodoWidgetProvider.ACTION_NEW_TODO -> "/editor/todo"
        else -> null
    }

    private fun readLegacyState(): Map<String, Any> {
        rebuildDatabaseForFlutterIfNeeded()
        val publicSettings = getSharedPreferences("note_list_filters", Context.MODE_PRIVATE)
        return buildMap {
            put("notesPath", java.io.File(filesDir, "notes").absolutePath)
            put("databasePath", getDatabasePath("reflect.db").absolutePath)
            put("migrationComplete", getSharedPreferences(MIGRATION_PREFS, Context.MODE_PRIVATE)
                .getBoolean(MIGRATION_COMPLETE, false))
            put("deselectedFolders", publicSettings.getStringSet("deselected_folders", emptySet())
                ?.toList() ?: emptyList<String>())
            put("secrets", readLegacySecrets())
        }
    }

    /**
     * Flutter's bundled SQLite does not provide the old Room FTS4 extension.
     * The canonical notes and all settings live outside this index, so rebuild
     * the index once rather than carrying its unavailable FTS triggers forward.
     */
    private fun rebuildDatabaseForFlutterIfNeeded() {
        val preferences = getSharedPreferences(MIGRATION_PREFS, Context.MODE_PRIVATE)
        if (preferences.getBoolean(DATABASE_REBUILT_FOR_FLUTTER, false)) return

        val database = getDatabasePath("reflect.db")
        if (database.exists() && !deleteDatabase("reflect.db")) return
        preferences.edit().putBoolean(DATABASE_REBUILT_FOR_FLUTTER, true).apply()
    }

    private fun readLegacySecrets(): Map<String, Any> = try {
        val key = MasterKey.Builder(this)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        val prefs = EncryptedSharedPreferences.create(
            this,
            "secret_prefs",
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
        buildMap {
            listOf(
                "github_token", "repo_owner", "repo_name", "ai_provider_url",
                "ai_provider_api_key", "ai_provider_model_id", "voice_provider",
                "voice_model_id", "voice_endpoint", "voice_api_key"
            ).forEach { name -> prefs.getString(name, null)?.let { put(name, it) } }
            put("voice_use_preview_key", prefs.getBoolean("voice_use_preview_key", true))
        }
    } catch (_: Exception) {
        // A fresh install has no legacy encrypted preferences.  Dart will display
        // normal onboarding instead of treating that as a migration failure.
        emptyMap()
    }

    private companion object {
        const val CHANNEL = "com.specular.android/legacy"
        const val WIDGET_CHANNEL = "com.specular.android/widget"
        const val DOCUMENT_CHANNEL = "com.specular.android/documents"
        const val CREATE_DOCUMENT_REQUEST = 4901
        const val OPEN_DOCUMENT_REQUEST = 4902
        const val MIGRATION_PREFS = "flutter_migration"
        const val MIGRATION_COMPLETE = "complete"
        const val DATABASE_REBUILT_FOR_FLUTTER = "database_rebuilt_for_flutter_v1"
    }
}
