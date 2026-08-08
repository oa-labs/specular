package com.specular.android.data.remote

import android.media.MediaRecorder
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import android.content.Context

/** Records a single temporary M4A file; callers must stop or cancel each recording. */
@Singleton
class VoiceRecorder @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var recorder: MediaRecorder? = null
    private var output: File? = null

    fun start(): File {
        cancel()
        val file = File(context.cacheDir, "voice-${UUID.randomUUID()}.m4a")
        try {
            recorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setOutputFile(file.absolutePath)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                prepare()
                start()
            }
            output = file
            return file
        } catch (error: Exception) {
            recorder?.release()
            recorder = null
            file.delete()
            throw error
        }
    }

    fun stop(): File {
        val activeRecorder = recorder ?: error("No recording is active")
        val file = output ?: error("No recording file is available")
        try {
            activeRecorder.stop()
            return file
        } catch (error: RuntimeException) {
            file.delete()
            throw IllegalStateException("Recording was too short to transcribe", error)
        } finally {
            activeRecorder.release()
            recorder = null
            output = null
        }
    }

    fun cancel() {
        try {
            recorder?.stop()
        } catch (_: RuntimeException) {
            // Stopping an incomplete recording can fail; its temporary file is discarded below.
        } finally {
            recorder?.release()
            recorder = null
            output?.delete()
            output = null
        }
    }
}
