import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/markdown.dart';

class AiSnippetService {
  AiSnippetService(this._storage, {Dio? dio}) : _dio = dio ?? Dio();

  final FlutterSecureStorage _storage;
  final Dio _dio;

  Future<bool> isConfigured() async {
    final values = await Future.wait([
      _storage.read(key: 'ai_provider_url'),
      _storage.read(key: 'ai_provider_api_key'),
      _storage.read(key: 'ai_provider_model_id'),
    ]);
    return values.every((value) => value?.trim().isNotEmpty == true);
  }

  Future<String> generate(String noteBody) async {
    final endpoint =
        (await _storage.read(key: 'ai_provider_url'))?.trim() ?? '';
    final apiKey =
        (await _storage.read(key: 'ai_provider_api_key'))?.trim() ?? '';
    final model =
        (await _storage.read(key: 'ai_provider_model_id'))?.trim() ?? '';
    if (endpoint.isEmpty || apiKey.isEmpty || model.isEmpty) {
      throw StateError('Configure an AI snippet provider in Settings first.');
    }
    final response = await _dio.post<Map<String, dynamic>>(
      endpoint,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content':
                'Provide a plain-text high-level phrase, under 7 words, summarizing the core subject of the content below for a UI list preview. Do not use Markdown. Do not include specific data points such as emails, dates, or phone numbers, and do not reference the note, its tags, or its type.\n\n$noteBody',
          },
        ],
      },
    );
    final choices = response.data?['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;
    final normalized = content is String
        ? content
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim()
              .replaceAll(RegExp(r'''^["']|["']$'''), '')
        : '';
    final plainText = MarkdownContract.plainText(normalized);
    if (plainText.isEmpty)
      throw StateError('The AI provider returned no snippet.');
    return plainText.split(' ').take(6).join(' ');
  }
}
