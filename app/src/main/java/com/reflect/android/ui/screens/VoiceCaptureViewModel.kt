package com.specular.android.ui.screens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.specular.android.data.remote.AiProviderSettings
import com.specular.android.data.remote.VoiceRecorder
import com.specular.android.data.remote.VoiceTranscriber
import com.specular.android.data.repo.NoteRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class VoiceCaptureKind { THOUGHT, TODO }

data class VoiceCaptureState(
    val recording: Boolean = false,
    val transcribing: Boolean = false,
    val saving: Boolean = false,
    val transcript: String = "",
    val error: String? = null
)

@HiltViewModel
class VoiceCaptureViewModel @Inject constructor(
    private val recorder: VoiceRecorder,
    private val transcriber: VoiceTranscriber,
    private val repo: NoteRepository,
    settings: AiProviderSettings
) : ViewModel() {
    private val _state = MutableStateFlow(VoiceCaptureState())
    val state: StateFlow<VoiceCaptureState> = _state
    val isConfigured: StateFlow<Boolean> = combine(settings.config, settings.voiceConfig) { _, _ ->
        settings.isVoiceConfigured()
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), settings.isVoiceConfigured())

    fun startRecording() {
        if (_state.value.recording || _state.value.transcribing) return
        try {
            recorder.start()
            _state.value = VoiceCaptureState(recording = true)
        } catch (error: Exception) {
            _state.value = VoiceCaptureState(error = error.message ?: "Could not start recording")
        }
    }

    fun stopAndTranscribe() {
        if (!_state.value.recording) return
        val audio = try {
            recorder.stop()
        } catch (error: Exception) {
            _state.value = VoiceCaptureState(error = error.message ?: "Could not finish recording")
            return
        }
        _state.value = VoiceCaptureState(transcribing = true)
        viewModelScope.launch {
            try {
                _state.value = VoiceCaptureState(transcript = transcriber.transcribe(audio))
            } catch (error: Exception) {
                _state.value = VoiceCaptureState(error = error.message ?: "Could not transcribe recording")
            } finally {
                audio.delete()
            }
        }
    }

    fun setTranscript(value: String) {
        _state.value = _state.value.copy(transcript = value, error = null)
    }

    fun saveToToday(kind: VoiceCaptureKind, onSaved: (String) -> Unit) {
        val transcript = _state.value.transcript.trim()
        if (transcript.isBlank() || _state.value.saving) return
        _state.value = _state.value.copy(saving = true, error = null)
        viewModelScope.launch {
            try {
                val markdown = when (kind) {
                    VoiceCaptureKind.THOUGHT -> transcript
                    VoiceCaptureKind.TODO -> "- [ ] $transcript"
                }
                onSaved(repo.appendToTodayNote(markdown).id)
            } catch (error: Exception) {
                _state.value = _state.value.copy(error = error.message ?: "Could not save capture")
            } finally {
                _state.value = _state.value.copy(saving = false)
            }
        }
    }

    fun discard() {
        recorder.cancel()
        _state.value = VoiceCaptureState()
    }

    override fun onCleared() {
        recorder.cancel()
        super.onCleared()
    }
}
