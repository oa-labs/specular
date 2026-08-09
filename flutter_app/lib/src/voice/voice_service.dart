import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceService {
  VoiceService(this._storage);
  final FlutterSecureStorage _storage;
  final AudioRecorder _recorder = AudioRecorder();

  Future<void> start() async {
    if (!await _recorder.hasPermission()) throw StateError('Microphone permission was not granted.');
    final cache = await getTemporaryDirectory();
    final path = '${cache.path}${Platform.pathSeparator}voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
  }

  Future<String> stopAndTranscribe() async {
    final path = await _recorder.stop();
    if (path == null) throw StateError('No voice recording was created.');
    final audio = File(path);
    try {
      return await _transcribe(audio);
    } finally {
      if (await audio.exists()) await audio.delete();
    }
  }

  Future<void> cancel() => _recorder.cancel();
  Future<void> dispose() => _recorder.dispose();

  Future<String> _transcribe(File audio) async {
    final provider = await _storage.read(key: 'voice_provider');
    final model = await _storage.read(key: 'voice_model_id');
    final customEndpoint = await _storage.read(key: 'voice_endpoint');
    final usePreviewKey = await _storage.read(key: 'voice_use_preview_key') != 'false';
    final key = usePreviewKey
        ? await _storage.read(key: 'ai_provider_api_key')
        : await _storage.read(key: 'voice_api_key');
    final endpoint = switch (provider) {
      'OPENROUTER' => 'https://openrouter.ai/api/v1/audio/transcriptions',
      'OPENAI' => 'https://api.openai.com/v1/audio/transcriptions',
      _ => customEndpoint,
    };
    if (endpoint == null || endpoint.isEmpty || key == null || key.isEmpty || model == null || model.isEmpty) {
      throw StateError('Configure a voice provider, model, and API key in Settings.');
    }
    final dio = Dio();
    final response = provider == 'OPENROUTER'
        ? await dio.post<Map<String, dynamic>>(
            endpoint,
            data: {'input_audio': {'data': base64Encode(await audio.readAsBytes()), 'format': 'm4a'}, 'model': model},
            options: Options(headers: {'Authorization': 'Bearer $key'}),
          )
        : await dio.post<Map<String, dynamic>>(
            endpoint,
            data: FormData.fromMap({'model': model, 'file': await MultipartFile.fromFile(audio.path, filename: audio.uri.pathSegments.last)}),
            options: Options(headers: {'Authorization': 'Bearer $key'}),
          );
    final text = response.data?['text'] as String?;
    if (text == null || text.trim().isEmpty) throw StateError('The transcription provider returned no text.');
    return text.trim();
  }
}
