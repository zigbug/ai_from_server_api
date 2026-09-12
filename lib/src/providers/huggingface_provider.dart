import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'provider.dart';

/// Провайдер Hugging Face Inference Providers.
///
/// Текст идёт через OpenAI-совместимый роутер `/v1/chat/completions`,
/// где HF сам выбирает подходящий серверный провайдер. Генерация и
/// редактирование изображений идут через Inference Providers
/// (fal-ai, replicate, wavespeed и др.) по классической схеме
/// `router.huggingface.co/{provider}/{providerModelId}`.
class HuggingFaceProvider implements LLMProvider, ImageProvider {
  HuggingFaceProvider(this.token);

  final String? token;

  static const _router = 'https://router.huggingface.co';
  static const _chatUrl = '$_router/v1/chat/completions';
  static const _modelInfoUrl = 'https://huggingface.co/api/models';

  /// Приоритет провайдеров для генерации картинок.
  static const _preferredImageProviders = ['fal-ai', 'together', 'replicate', 'wavespeed', 'nscale'];

  /// Известные маппинги «ID модели / задача → провайдер» для статических
  /// моделей каталога (не требуют сетевого запроса).
  static const Map<String, ({String provider, String id})> _knownMapping = {
    'black-forest-labs/FLUX.1-schnell/text-to-image': (
      provider: 'fal-ai',
      id: 'fal-ai/flux/schnell',
    ),
    'black-forest-labs/FLUX.1-dev/text-to-image': (
      provider: 'fal-ai',
      id: 'fal-ai/flux/dev',
    ),
    'stabilityai/stable-diffusion-xl-base-1.0/text-to-image': (
      provider: 'fal-ai',
      id: 'fal-ai/fast-sdxl',
    ),
    'black-forest-labs/FLUX.1-Kontext-dev/image-to-image': (
      provider: 'fal-ai',
      id: 'fal-ai/flux-kontext/dev',
    ),
    'Qwen/Qwen-Image-Edit/image-to-image': (
      provider: 'fal-ai',
      id: 'fal-ai/qwen-image-edit',
    ),
  };

  /// Кэш сетевого резолва маппинга моделей.
  final Map<String, ({String provider, String id})> _resolved = {};

  /// Сбросить кэш сетевого резолва провайдеров (при `?refresh=1`).
  void invalidateProviderMapping() {
    _resolved.clear();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

  /// Дождаться готовности модели (ретракции при 503).
  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() send,
  ) async {
    const maxAttempts = 30;
    for (var i = 0; i < maxAttempts; i++) {
      final resp = await send();
      if (resp.statusCode == 503) {
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
    final body = jsonEncode({
      'model': model,
      'messages': [
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages.map((m) => {'role': m.role.name, 'content': m.content}),
      ],
      'max_tokens': 2048,
    });

    final resp = await _requestWithRetry(
      () => http.post(Uri.parse(_chatUrl), headers: _headers, body: body),
    );

    if (resp.statusCode != 200) {
      throw Exception('HuggingFace error ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List? ?? const [];
    if (choices.isEmpty) {
      throw Exception('HuggingFace: empty completion result');
    }
    final first = choices.first as Map<String, dynamic>;
    final message = first['message'] as Map<String, dynamic>? ?? const {};
    final text = message['content'] as String? ?? '';
    return TextResult(text: text.trim(), provider: 'huggingface');
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

    final result = await chat(
      messages: [ChatMessage(role: MessageRole.user, content: prompt)],
      model: model,
    );
    return result.text;
  }

  @override
  Future<ImageResult> generateImage({
    required String prompt,
    required String model,
  }) async {
    final resolved = await _resolveModel(model, 'text-to-image');

    final resp = await _requestWithRetry(
      () => http.post(
        Uri.parse('$_router/${resolved.provider}/${resolved.id}'),
        headers: _headers,
        body: jsonEncode({'prompt': prompt}),
      ),
    );

    if (resp.statusCode != 200) {
      throw Exception('HuggingFace image error ${resp.statusCode}: ${resp.body}');
    }

    return _extractImage(resp);
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
    final resolved = await _resolveModel(model, 'image-to-image');

    final b64 = base64Encode(image);
    final dataUri = 'data:${_sniffMime(image)};base64,$b64';

    final resp = await _requestWithRetry(
      () => http.post(
        Uri.parse('$_router/${resolved.provider}/${resolved.id}'),
        headers: _headers,
        body: jsonEncode({
          'prompt': prompt,
          'image_url': dataUri,
          'image_urls': [dataUri],
          'strength': guidanceScale ?? 0.75,
        }),
      ),
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'HuggingFace image edit error ${resp.statusCode}: ${resp.body}',
      );
    }

    return _extractImage(resp);
  }

  /// Разобрать ответ генератора: либо скачать картинку по `images[0].url`,
  /// либо вернуть байты напрямую (некоторые провайдеры отдают картинку).
  Future<ImageResult> _extractImage(http.Response resp) async {
    final contentType = resp.headers['content-type'] ?? '';
    if (!contentType.startsWith('image/')) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        final images = decoded['images'];
        if (images is List && images.isNotEmpty) {
          final first = images.first;
          final url = first is Map
              ? first['url'] as String?
              : (first as String);
          if (url != null && url.isNotEmpty) {
            final img = await http
                .get(Uri.parse(url))
                .timeout(const Duration(seconds: 60));
            if (img.statusCode == 200) {
              return ImageResult(
                bytes: img.bodyBytes,
                mimeType: _sniffMime(img.bodyBytes),
                provider: 'huggingface',
              );
            }
          }
        }
      }
      throw Exception('HuggingFace: unexpected image response: ${resp.body}');
    }
    return ImageResult(
      bytes: resp.bodyBytes,
      mimeType: _detectMimeType(contentType),
      provider: 'huggingface',
    );
  }

  /// Найти провайдера для модели/задачи. Сначала смотрит в статический
  /// маппинг, затем опрашивает HF Hub (информация кэшируется в памяти).
  Future<({String provider, String id})> _resolveModel(
    String model,
    String task,
  ) async {
    final known = _knownMapping['$model/$task'];
    if (known != null) return known;

    final cached = _resolved['$task|$model'];
    if (cached != null) return cached;

    try {
      final uri = Uri.parse('$_modelInfoUrl/$model').replace(
        queryParameters: {'expand': 'inferenceProviderMapping'},
      );
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final info = jsonDecode(resp.body) as Map<String, dynamic>;
        final mapping = info['inferenceProviderMapping'];
        if (mapping is Map<String, dynamic>) {
          for (final provider in _preferredImageProviders) {
            final entry = mapping[provider];
            if (entry is Map<String, dynamic>) {
              final status = entry['status'] as String?;
              if (status != null && status != 'live') continue;
              final id = entry['providerId'] as String?;
              if (id != null && id.isNotEmpty) {
                final r = (provider: provider, id: id);
                _resolved['$task|$model'] = r;
                return r;
              }
            }
          }
        }
      }
    } on Exception {
      // Сеть недоступна — даём понятную ошибку ниже.
    }

    throw Exception(
      'HuggingFace: no supported provider found for "$model" '
      '($task task)',
    );
  }

  static String _sniffMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  String _detectMimeType(String? contentType) {
    if (contentType == null) return 'image/png';
    final first = contentType.split(';').first.trim();
    if (first.startsWith('image/')) return first;
    return 'image/png';
  }
}