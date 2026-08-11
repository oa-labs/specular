import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

/// A recording is durable before any network operation begins.  The manifest
/// makes an interrupted upload/restart recoverable instead of treating audio as
/// an ephemeral UI detail.
class VoiceSession {
  VoiceSession({
    required this.id,
    required this.createdAt,
    this.noteId,
    this.state = VoiceSessionState.recording,
    this.transcript = '',
    this.error,
    List<VoiceSegment>? segments,
  }) : segments = segments ?? [];

  final String id;
  final DateTime createdAt;
  final String? noteId;
  VoiceSessionState state;
  String transcript;
  String? error;
  final List<VoiceSegment> segments;

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'noteId': noteId,
    'state': state.name,
    'transcript': transcript,
    'error': error,
    'segments': [for (final segment in segments) segment.toJson()],
  };

  factory VoiceSession.fromJson(Map<String, dynamic> json) => VoiceSession(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    noteId: json['noteId'] as String?,
    state: VoiceSessionState.values.byName(
      json['state'] as String? ?? VoiceSessionState.pending.name,
    ),
    transcript: json['transcript'] as String? ?? '',
    error: json['error'] as String?,
    segments: [
      for (final raw in json['segments'] as List? ?? const [])
        VoiceSegment.fromJson(Map<String, dynamic>.from(raw as Map)),
    ],
  );
}

enum VoiceSessionState {
  recording,
  pending,
  transcribing,
  cleanup,
  complete,
  failed,
}

class VoiceSegment {
  VoiceSegment({
    required this.path,
    required this.startedAt,
    this.durationMs = 0,
    this.transcribed = false,
  });

  final String path;
  final DateTime startedAt;
  int durationMs;
  bool transcribed;

  Map<String, Object?> toJson() => {
    'path': path,
    'startedAt': startedAt.toIso8601String(),
    'durationMs': durationMs,
    'transcribed': transcribed,
  };

  factory VoiceSegment.fromJson(Map<String, dynamic> json) => VoiceSegment(
    path: json['path'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    durationMs: json['durationMs'] as int? ?? 0,
    transcribed: json['transcribed'] as bool? ?? false,
  );
}

class VoiceLiveUpdate {
  const VoiceLiveUpdate(this.text, {this.isFinal = false, this.status});
  final String text;
  final bool isFinal;
  final String? status;
}

class VoiceService {
  VoiceService(this._storage, {Dio? dio}) : _dio = dio ?? Dio();

  static const _platform = MethodChannel('com.specular.android/voice');
  static const _segmentDuration = Duration(minutes: 5);
  static const _minFreeBytes = 100 * 1024 * 1024;
  static const retryTask = 'voice_session_retry';

  final FlutterSecureStorage _storage;
  final Dio _dio;
  late final AudioRecorder _recorder = AudioRecorder();
  final _updates = StreamController<VoiceLiveUpdate>.broadcast();
  final _uuid = const Uuid();

  VoiceSession? _session;
  Directory? _sessionDirectory;
  IOSink? _sink;
  StreamSubscription<List<int>>? _audioSubscription;
  Timer? _segmentTimer;
  WebSocket? _socket;
  var _segmentBytes = 0;
  var _segmentStartedAt = DateTime.now();
  var _rotating = false;
  DateTime _lastStopCheck = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<VoiceLiveUpdate> get updates => _updates.stream;
  VoiceSession? get session => _session;
  bool get isRecording => _session?.state == VoiceSessionState.recording;

  Future<List<VoiceSession>> recoverableSessions() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(
      '${support.path}${Platform.pathSeparator}voice-sessions',
    );
    if (!await root.exists()) return const [];
    final sessions = <VoiceSession>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final manifest = File(
        '${entity.path}${Platform.pathSeparator}session.json',
      );
      if (!await manifest.exists()) continue;
      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is Map) {
          final session = VoiceSession.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (session.state != VoiceSessionState.complete) {
            sessions.add(session);
          }
        }
      } catch (_) {
        // A malformed manifest must never prevent discovery of other audio.
      }
    }
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  Future<String> retry(VoiceSession session) async {
    if (isRecording) {
      throw StateError('Stop the active recording before retrying.');
    }
    _session = session;
    _sessionDirectory = Directory(
      File(session.segments.first.path).parent.path,
    );
    try {
      await _processPendingSegments();
      session.state = VoiceSessionState.cleanup;
      await _persist();
      session.transcript = await _clean(session.transcript);
      session.state = VoiceSessionState.complete;
      await _persist();
      return session.transcript;
    } catch (error) {
      await _fail('Voice processing is pending: $error');
      rethrow;
    }
  }

  static Future<bool> processBackgroundRetry(
    FlutterSecureStorage storage,
    Map<String, dynamic>? inputData,
  ) async {
    final path = inputData?['sessionDirectory'] as String?;
    if (path == null || path.isEmpty) return true;
    final directory = Directory(path);
    final manifest = File(
      '${directory.path}${Platform.pathSeparator}session.json',
    );
    if (!await manifest.exists()) return true;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map) return true;
      final service = VoiceService(storage);
      service._sessionDirectory = directory;
      service._session = VoiceSession.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (service._session!.state == VoiceSessionState.complete) return true;
      await service._processPendingSegments();
      service._session!.state = VoiceSessionState.cleanup;
      await service._persist();
      service._session!.transcript = await service._clean(
        service._session!.transcript,
      );
      service._session!.state = VoiceSessionState.complete;
      service._session!.error = null;
      await service._persist();
      return true;
    } catch (_) {
      // Returning false makes WorkManager apply its exponential retry policy.
      return false;
    }
  }

  Future<void> start({String? noteId}) async {
    if (isRecording) return;
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was not granted.');
    }
    final freeBytes = await _availableBytes();
    if (freeBytes != null && freeBytes < _minFreeBytes) {
      throw StateError('Free at least 100 MB of storage before recording.');
    }
    final key = await _openAiKey();
    if (key == null) {
      throw StateError(
        'Configure a dedicated OpenAI voice API key in Settings.',
      );
    }
    final support = await getApplicationSupportDirectory();
    final id = _uuid.v4();
    _sessionDirectory = Directory(
      '${support.path}${Platform.pathSeparator}voice-sessions${Platform.pathSeparator}$id',
    );
    await _sessionDirectory!.create(recursive: true);
    _session = VoiceSession(id: id, createdAt: DateTime.now(), noteId: noteId);
    await _persist();
    await _startForegroundService(id);
    await _connectLiveTranscription(key);
    await _startSegment();
    _updates.add(const VoiceLiveUpdate('', status: 'Recording'));
  }

  Future<void> _startSegment() async {
    final directory = _sessionDirectory;
    final session = _session;
    if (directory == null || session == null) return;
    _segmentStartedAt = DateTime.now();
    final partPath =
        '${directory.path}${Platform.pathSeparator}${session.segments.length.toString().padLeft(4, '0')}.wav.part';
    _sink = File(partPath).openWrite();
    // A WAV header is written when the segment is finalized, once its byte
    // count is known. This keeps the on-disk recording streamable and uploadable.
    _sink!.add(List<int>.filled(44, 0));
    _segmentBytes = 0;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 24000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.pause,
      ),
    );
    _audioSubscription = stream.listen(
      _writeAudio,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_fail('Recording failed: $error'));
      },
    );
    _segmentTimer = Timer(_segmentDuration, () => unawaited(_rotateSegment()));
  }

  void _writeAudio(List<int> bytes) {
    _sink?.add(bytes);
    _segmentBytes += bytes.length;
    final socket = _socket;
    if (socket != null) {
      try {
        socket.add(
          jsonEncode({
            'type': 'input_audio_buffer.append',
            'audio': base64Encode(bytes),
          }),
        );
      } catch (_) {
        _updates.add(
          const VoiceLiveUpdate('', status: 'Live transcription reconnecting…'),
        );
      }
    }
    if (DateTime.now().difference(_lastStopCheck) >=
        const Duration(seconds: 1)) {
      _lastStopCheck = DateTime.now();
      unawaited(_checkForegroundStop());
    }
  }

  Future<void> _checkForegroundStop() async {
    try {
      final requested =
          await _platform.invokeMethod<bool>('foregroundStopRequested') ??
          false;
      if (requested && isRecording) {
        // The final audio is already on disk; processing can fail safely and
        // remain discoverable from the recovery UI.
        await stopAndTranscribe();
      }
    } on MissingPluginException {
      // Non-Android platforms do not provide the foreground notification.
    }
  }

  Future<void> _rotateSegment() async {
    if (_rotating || !isRecording) return;
    _rotating = true;
    try {
      _segmentTimer?.cancel();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _recorder.stop();
      await _finishSegment();
      await _startSegment();
    } catch (error) {
      await _fail('Could not finalize a recording segment: $error');
    } finally {
      _rotating = false;
    }
  }

  Future<void> _finishSegment() async {
    final directory = _sessionDirectory;
    final session = _session;
    final sink = _sink;
    if (directory == null || session == null || sink == null) return;
    _sink = null;
    await sink.flush();
    await sink.close();
    if (_segmentBytes == 0) return;
    final index = session.segments.length.toString().padLeft(4, '0');
    final part = File(
      '${directory.path}${Platform.pathSeparator}$index.wav.part',
    );
    final completed = File(
      '${directory.path}${Platform.pathSeparator}$index.wav',
    );
    final handle = await part.open(mode: FileMode.write);
    try {
      await handle.setPosition(0);
      await handle.writeFrom(_wavHeader(_segmentBytes));
      await handle.flush();
    } finally {
      await handle.close();
    }
    await part.rename(completed.path);
    session.segments.add(
      VoiceSegment(
        path: completed.path,
        startedAt: _segmentStartedAt,
        durationMs: DateTime.now().difference(_segmentStartedAt).inMilliseconds,
      ),
    );
    await _persist();
  }

  List<int> _wavHeader(int dataLength) {
    final bytes = ByteData(44);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    text(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, 24000, Endian.little);
    bytes.setUint32(28, 48000, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    return bytes.buffer.asUint8List();
  }

  Future<String> stopAndTranscribe() async {
    final session = _session;
    if (session == null) throw StateError('No voice recording is active.');
    _segmentTimer?.cancel();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    await _finishSegment();
    session.state = VoiceSessionState.pending;
    await _persist();
    try {
      _socket?.add(jsonEncode({'type': 'input_audio_buffer.commit'}));
    } catch (_) {}
    await _socket?.close();
    _socket = null;
    await _stopForegroundService();

    // Realtime finals are preferred, but every durable segment is replayed via
    // the file API if the live session was offline or incomplete.
    try {
      await _processPendingSegments();
      session.state = VoiceSessionState.cleanup;
      await _persist();
      final cleaned = await _clean(session.transcript);
      session.transcript = cleaned;
      session.state = VoiceSessionState.complete;
      await _persist();
      _updates.add(
        VoiceLiveUpdate(cleaned, isFinal: true, status: 'Ready to save'),
      );
      return cleaned;
    } catch (error) {
      await _fail('Voice processing is pending: $error');
      await _enqueueRetry();
      rethrow;
    }
  }

  /// The caller invokes this only after the cleaned transcript has been
  /// committed to a canonical Markdown note.  Until then every audio segment
  /// is intentionally retained for retry/recovery.
  Future<void> acknowledgeSaved() async {
    final session = _session;
    final directory = _sessionDirectory;
    if (session?.state != VoiceSessionState.complete || directory == null) {
      return;
    }
    for (final segment in session!.segments) {
      final file = File(segment.path);
      if (await file.exists()) await file.delete();
    }
    final manifest = File(
      '${directory.path}${Platform.pathSeparator}session.json',
    );
    if (await manifest.exists()) await manifest.delete();
    if (await directory.exists()) await directory.delete();
    _session = null;
    _sessionDirectory = null;
  }

  Future<void> _processPendingSegments() async {
    final session = _session!;
    session.state = VoiceSessionState.transcribing;
    await _persist();
    final parts = <String>[];
    for (final segment in session.segments.where(
      (segment) => !segment.transcribed,
    )) {
      final text = await _transcribeFile(File(segment.path));
      if (text.isNotEmpty) parts.add(text);
      segment.transcribed = true;
      await _persist();
    }
    // File transcription is canonical: it handles live-stream disconnects and
    // is the durable final transcript.
    if (parts.isNotEmpty) session.transcript = parts.join('\n\n').trim();
    if (session.transcript.isEmpty) {
      throw StateError(
        'No speech was transcribed. The audio remains available to retry.',
      );
    }
  }

  Future<String> _transcribeFile(File audio) async {
    final key = await _openAiKey();
    if (key == null) throw StateError('OpenAI voice API key is missing.');
    final model = (await _storage.read(key: 'voice_file_model'))?.trim();
    final response = await _dio.post<Map<String, dynamic>>(
      'https://api.openai.com/v1/audio/transcriptions',
      data: FormData.fromMap({
        'model': model?.isNotEmpty == true ? model : 'gpt-transcribe',
        'file': await MultipartFile.fromFile(
          audio.path,
          filename: audio.uri.pathSegments.last,
        ),
      }),
      options: Options(headers: {'Authorization': 'Bearer $key'}),
    );
    return (response.data?['text'] as String? ?? '').trim();
  }

  Future<String> _clean(String transcript) async {
    if (transcript.trim().isEmpty) return transcript;
    final key = await _openAiKey();
    if (key == null) throw StateError('OpenAI voice API key is missing.');
    final model = (await _storage.read(key: 'voice_cleanup_model'))?.trim();
    final response = await _dio.post<Map<String, dynamic>>(
      'https://api.openai.com/v1/chat/completions',
      options: Options(headers: {'Authorization': 'Bearer $key'}),
      data: {
        'model': model?.isNotEmpty == true ? model : 'gpt-5-mini',
        'messages': [
          {
            'role': 'system',
            'content':
                'Lightly clean a speech transcript. Preserve every fact, name, number, uncertainty, and speaker label. Do not summarize, add facts, or remove meaning. Only correct punctuation/capitalization and add short Markdown paragraphs. Return only the cleaned transcript.',
          },
          {'role': 'user', 'content': transcript},
        ],
      },
    );
    final choices = response.data?['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;
    final cleaned = content is String ? content.trim() : '';
    if (cleaned.isEmpty) {
      throw StateError('The cleanup provider returned no text.');
    }
    return cleaned;
  }

  Future<void> _connectLiveTranscription(String key) async {
    try {
      final model = (await _storage.read(key: 'voice_model_id'))?.trim();
      final socket = await WebSocket.connect(
        'wss://api.openai.com/v1/realtime?model=${Uri.encodeQueryComponent(model?.isNotEmpty == true ? model! : 'gpt-live-transcribe')}',
        headers: {'Authorization': 'Bearer $key'},
      );
      _socket = socket;
      socket.add(
        jsonEncode({
          'type': 'session.update',
          'session': {
            'type': 'transcription',
            'audio': {
              'input': {
                'format': {'type': 'audio/pcm', 'rate': 24000},
                'transcription': {
                  'model': model?.isNotEmpty == true
                      ? model
                      : 'gpt-live-transcribe',
                  'delay': 'low',
                },
                'turn_detection': {'type': 'server_vad'},
              },
            },
          },
        }),
      );
      socket.listen(
        _handleRealtimeEvent,
        onDone: () {
          if (isRecording) {
            _updates.add(
              const VoiceLiveUpdate(
                '',
                status: 'Live transcription reconnecting…',
              ),
            );
          }
        },
        onError: (_) {
          if (isRecording) {
            _updates.add(
              const VoiceLiveUpdate(
                '',
                status:
                    'Live transcription unavailable; audio is safe locally.',
              ),
            );
          }
        },
      );
    } catch (_) {
      _updates.add(
        const VoiceLiveUpdate(
          '',
          status: 'Live transcription unavailable; audio is safe locally.',
        ),
      );
    }
  }

  void _handleRealtimeEvent(dynamic raw) {
    if (raw is! String) return;
    final event = jsonDecode(raw);
    if (event is! Map) return;
    final type = event['type'];
    if (type == 'conversation.item.input_audio_transcription.delta') {
      _updates.add(VoiceLiveUpdate(event['delta'] as String? ?? ''));
    } else if (type ==
        'conversation.item.input_audio_transcription.completed') {
      final text = event['transcript'] as String? ?? '';
      if (text.isNotEmpty) _updates.add(VoiceLiveUpdate(text, isFinal: true));
    }
  }

  Future<void> _persist() async {
    final directory = _sessionDirectory;
    final session = _session;
    if (directory == null || session == null) return;
    final target = File(
      '${directory.path}${Platform.pathSeparator}session.json',
    );
    final temporary = File('${target.path}.part');
    await temporary.writeAsString(jsonEncode(session.toJson()), flush: true);
    // Android's underlying POSIX rename replaces the old manifest atomically.
    // Deleting it first would create a crash window with no recovery record.
    await temporary.rename(target.path);
  }

  Future<void> _fail(String message) async {
    final session = _session;
    if (session == null) return;
    session.error = message;
    session.state = VoiceSessionState.failed;
    await _persist();
    _updates.add(VoiceLiveUpdate('', status: message));
  }

  Future<void> _enqueueRetry() async {
    final directory = _sessionDirectory;
    final session = _session;
    if (directory == null || session == null) return;
    await Workmanager().registerOneOffTask(
      'voice_retry_${session.id}',
      retryTask,
      inputData: {'sessionDirectory': directory.path},
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Future<int?> _availableBytes() async {
    try {
      return await _platform.invokeMethod<int>('availableBytes');
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _startForegroundService(String id) async {
    try {
      await _platform.invokeMethod<void>('startForegroundRecording', {
        'sessionId': id,
      });
    } on MissingPluginException {
      // Foreground-service support is Android-specific; recording still works
      // where the platform bridge is unavailable.
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await _platform.invokeMethod<void>('stopForegroundRecording');
    } on MissingPluginException {
      // Nothing to stop when the host platform has no foreground service.
    }
  }

  Future<String?> _openAiKey() async {
    final direct = (await _storage.read(key: 'voice_openai_api_key'))?.trim();
    if (direct?.isNotEmpty == true) return direct;
    final provider = await _storage.read(key: 'voice_provider');
    if (provider == 'OPENAI') {
      return (await _storage.read(key: 'voice_api_key'))?.trim();
    }
    return null;
  }

  /// Deliberately does not delete files. A user can leave the screen, lose
  /// connectivity, or restart the app without discarding a recording.
  Future<void> cancel() async {
    // Deliberately no-op. A routed-away capture remains recoverable instead of
    // silently stopping/deleting the active session.
  }

  Future<void> dispose() async {
    _segmentTimer?.cancel();
    await _audioSubscription?.cancel();
    await _socket?.close();
    await _recorder.dispose();
    await _updates.close();
  }
}
