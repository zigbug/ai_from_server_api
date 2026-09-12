import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'provider.dart';

/// Провайдер Groq (OpenAI-совместимый chat completions).
///
/// Используется только для текстовых моделей — картинки пока остаются
/// на Hugging Face.
class GroqProvider implements LLMProvider {
  GroqProvider(this.apiKey);

  final String? apiKey;

  static const _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _modelsUrl = 'https://api.groq.com/openai/v1/models';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': apiKey == null ? '' : 'Bearer $apiKey',
      };

  /// Список моделей, доступных на аккаунте. Без ключа или при ошибке —
  /// возвращает пустой список (используется статический fallback).
  Future<List<String>> listModels() async {
    if (apiKey == null || apiKey!.isEmpty) return [];
    try {
      final resp = await http
          .get(Uri.parse(_modelsUrl), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = (data['data'] as List? ?? []);
      return list
          .map((e) => (e as Map)['id'] as String?)
          .whereType<String>()
          .toList();
    } on Exception {
      return [];
    }
  }

  @override
  Future<TextResult> chat({
    required List<ChatMessage> messages,
    required String model,
    String? systemPrompt,
  }) async {
    final apiMessages = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }
    for (final m in messages) {
      apiMessages.add({'role': m.role.name, 'content': m.content});
    }

    final body = jsonEncode({
      'model': model,
      'messages': apiMessages,
      'max_tokens': 2048,
    });

    final resp = await http.post(
      Uri.parse(_baseUrl),
      headers: _headers,
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('Groq error ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('Groq: empty choices');
    }
    final text = (choices.first as Map)['message']['content'] as String? ?? '';
    return TextResult(text: text.trim(), provider: 'groq');
  }

  @override
  Future<String> summarize({
    required List<ChatMessage> messages,
    required String model,
  }) async {
    final transcript = messages
        .map((m) => '${m.role.name}: ${m.content}')
        .join('\n');
    final apiMessages = [
      {
        'role': 'system',
        'content':
            'You are an assistant that summarizes conversation history '
            'into a concise summary preserving all key facts, decisions and '
            'context. Output only the summary, no preamble.',
      },
      {
        'role': 'user',
        'content':
            'Summarize the following conversation into a brief summary:\n\n$transcript',
      },
    ];

    final body = jsonEncode({
      'model': model,
      'messages': apiMessages,
      'max_tokens': 1024,
    });

    final resp = await http.post(
      Uri.parse(_baseUrl),
      headers: _headers,
      body: body,
    );

    if (resp.statusCode != 200) {
      throw Exception('Groq summarize error ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('Groq: empty choices during summary');
    }
    final text = (choices.first as Map)['message']['content'] as String? ?? '';
    return text.trim();
  }
}