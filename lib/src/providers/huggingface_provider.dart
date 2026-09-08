import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'provider.dart';

/// Провайдер Hugging Face Inference API.
///
/// Используется для генерации изображений и части текстовых моделей.
class HuggingFaceProvider implements LLMProvider, ImageProvider {
  HuggingFaceProvider(this.token);

  final String? token;

  static const _baseUrl = 'https://api-inference.huggingface.co/models/';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': token == null ? '' : 'Bearer $token',
      };

  /// Дождаться готовности модели (ретракции при 503). HF Inference
  /// возвращает 503, пока модель загружается.
  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() send,
  ) async {
    const maxAttempts = 30;
    for (var i = 0; i < maxAttempts; i++) {
      final resp = await send();
      if (resp.statusCode == 503) {
        // Модель ещё загружается — ждём и пробуем снова.
        await Future<void>.delayed(const Duration(seconds: 3));
        continue;
      }
      return resp;
    }
    throw Exception('HuggingFace: model loading timeout');
  }

  @override
  Future<TextResult> chat({
    required List<ChatMessage> messages,
    required String model,
    String? systemPrompt,
  }) async {
    // Собираем полный промт (обычные text-generation модели HF принимают
    // одиночный текст, диалоги передаём как json в поле inputs).
    final prompt = _buildChatPrompt(messages, systemPrompt);

    final body = jsonEncode({
      'inputs': prompt,
      'parameters': {'max_new_tokens': 2048, 'return_full_text': false},
    });

    final resp = await _requestWithRetry(
      () => http.post(
        Uri.parse('$_baseUrl$model'),
        headers: _headers,
        body: body,
      ),
    );

    if (resp.statusCode != 200) {
      throw Exception('HuggingFace error ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    // Singer-generator возвращает список; берём первый элемент.
    final list = decoded as List;
    if (list.isEmpty) {
      throw Exception('HuggingFace: empty generation result');
    }
    final first = list.first as Map<String, dynamic>;
    final text = first['generated_text'] as String? ?? '';
    return TextResult(text: text.trim(), provider: 'huggingface');
  }

  String _buildChatPrompt(
    List<ChatMessage> messages,
    String? systemPrompt,
  ) {
    final buffer = StringBuffer();
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln(systemPrompt);
    }
    for (final m in messages) {
      buffer.writeln('${m.role.name}: ${m.content}');
    }
    buffer.writeln('assistant: ');
    return buffer.toString();
  }

  @override
  Future<String> summarize({
    required List<ChatMessage> messages,
    required String model,
  }) async {
    final transcript = messages
        .map((m) => '${m.role.name}: ${m.content}')
        .join('\n');
    final prompt =
        'Summarize the following conversation into a concise summary '
        'preserving key facts and context. Output only the summary:\n\n$transcript';

    final body = jsonEncode({
      'inputs': prompt,
      'parameters': {'max_new_tokens': 1024, 'return_full_text': false},
    });

    final resp = await _requestWithRetry(
      () => http.post(
        Uri.parse('$_baseUrl$model'),
        headers: _headers,
        body: body,
      ),
    );

    if (resp.statusCode != 200) {
      throw Exception('HuggingFace summarize error ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as List;
    if (decoded.isEmpty) {
      throw Exception('HuggingFace: empty summary result');
    }
    final text = (decoded.first as Map)['generated_text'] as String? ?? '';
    return text.trim();
  }

  @override
  Future<ImageResult> generateImage({
    required String prompt,
    required String model,
  }) async {
    final body = jsonEncode({'inputs': prompt});

    final resp = await _requestWithRetry(
      () => http.post(
        Uri.parse('$_baseUrl$model'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token == null ? '' : 'Bearer $token',
        },
        body: body,
      ),
    );

    if (resp.statusCode != 200) {
      throw Exception('HuggingFace image error ${resp.statusCode}: ${resp.body}');
    }

    return ImageResult(
      bytes: resp.bodyBytes,
      mimeType: _detectMimeType(resp.headers['content-type']),
      provider: 'huggingface',
    );
  }

  String _detectMimeType(String? contentType) {
    if (contentType == null) return 'image/png';
    final first = contentType.split(';').first.trim();
    if (first.startsWith('image/')) return first;
    return 'image/png';
  }

  @override
  Future<ImageResult> editImage({
    required String prompt,
    required Uint8List image,
    required String model,
    String? negativePrompt,
    double? guidanceScale,
    int? numInferenceSteps,
    int? width,
    int? height,
  }) async {
    final inputs = base64Encode(image);
    final params = <String, Object?>{
      'prompt': prompt,
      'negative_prompt': ?negativePrompt,
      'guidance_scale': ?guidanceScale,
      'num_inference_steps': ?numInferenceSteps,
      if (width != null && height != null)
        'target_size': {'width': width, 'height': height},
    };

    final body = jsonEncode({'inputs': inputs, 'parameters': params});

    final resp = await _requestWithRetry(
      () => http.post(
        Uri.parse('$_baseUrl$model'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token == null ? '' : 'Bearer $token',
        },
        body: body,
      ),
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'HuggingFace image edit error ${resp.statusCode}: ${resp.body}',
      );
    }

    return ImageResult(
      bytes: resp.bodyBytes,
      mimeType: _detectMimeType(resp.headers['content-type']),
      provider: 'huggingface',
    );
  }
}
