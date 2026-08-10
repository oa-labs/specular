package com.specular.android.voice

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.specular.android.MainActivity
import com.specular.android.R

/**
 * Keeps a user-visible Android foreground-service lease while Flutter owns the
 * PCM stream and durable segment writer.  Keeping this boundary native avoids
 * relying on an Activity's visibility for long recordings.
 */
class VoiceRecordingService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, VoiceRecordingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        if (intent?.action == ACTION_STOP) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putBoolean(STOP_REQUESTED, true).apply()
            stopSelf()
            return START_NOT_STICKY
        }
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(STOP_REQUESTED, false).apply()
        startForeground(
            NOTIFICATION_ID,
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_launcher_round)
                .setContentTitle("Voice recording in progress")
                .setContentText("Specular is saving audio locally")
                .setContentIntent(openApp)
                .setOngoing(true)
                .addAction(0, "Stop", stop)
                .build(),
        )
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun createChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Voice recording", NotificationManager.IMPORTANCE_LOW),
        )
    }

    companion object {
        private const val CHANNEL_ID = "voice_recording"
        private const val NOTIFICATION_ID = 2201
        private const val ACTION_STOP = "com.specular.android.voice.STOP"
        private const val PREFS = "voice_recording"
        private const val STOP_REQUESTED = "stop_requested"

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, VoiceRecordingService::class.java),
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, VoiceRecordingService::class.java))
        }

        fun stopRequested(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(STOP_REQUESTED, false)
    }
}
