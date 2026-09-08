import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'provider.dart';

/// Провайдер для OpenRouter (включая бесплатные модели).
class OpenRouterProvider implements LLMProvider {
  OpenRouterProvider(this.apiKey);

  final String? apiKey;
  static const _baseUrl = 'https://openrouter.ai/api/v1/chat/completions';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': apiKey == null ? '' : 'Bearer $apiKey',
      };

  @override
  Future<TextResult> chat({
    required List<ChatMessage> messages,
    required String model,
    String? systemPrompt,
  }) async {
    // Формируем массив сообщений для API.
    final apiMessages = <Map<String, String>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }

    // Встраиваем резюме (если оно передано как system-часть) — содержится
    // в systemPrompt уже, здесь не дублируем.
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
      throw Exception(
        'OpenRouter error ${resp.statusCode}: ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('OpenRouter: empty choices');
    }
    final text = (choices.first as Map)['message']['content'] as String? ?? '';
    return TextResult(text: text.trim(), provider: 'openrouter');
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
      throw Exception(
        'OpenRouter summarize error ${resp.statusCode}: ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    if (choices.isEmpty) {
      throw Exception('OpenRouter: empty choices during summary');
    }
    final text = (choices.first as Map)['message']['content'] as String? ?? '';
    return text.trim();
  }
}
