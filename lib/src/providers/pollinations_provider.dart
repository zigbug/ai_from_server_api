import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'provider.dart';

/// Провайдер генерации картинок Pollinations (https://pollinations.ai).
///
/// Бесплатный text-to-image без ключа, доступный из России.
/// Таск image-to-image (edit) Pollinations не поддерживает — при вызове
/// бросается [UnsupportedError].
class PollinationsImageProvider implements ImageProvider {
  static const _baseUrl = 'https://image.pollinations.ai/prompt/';

  static const supportedModel = 'sana';

  @override
  Future<ImageResult> generateImage({
    required String prompt,
    required String model,
  }) async {
    final params = <String, String>{
      'width': '768',
      'height': '768',
      'model': 'sana',
    };

    final uri = Uri.parse(
      '$_baseUrl${Uri.encodeComponent(prompt)}',
    ).replace(queryParameters: params);

    final resp = await http.get(uri).timeout(const Duration(seconds: 90));
    if (resp.statusCode != 200) {
      throw Exception(
        'Pollinations image error ${resp.statusCode}: ${resp.body}',
      );
    }

    return ImageResult(
      bytes: Uint8List.fromList(resp.bodyBytes),
      mimeType: _detectMimeType(resp.headers['content-type']),
      provider: 'pollinations',
    );
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
  }) {
    throw UnsupportedError(
      'Pollinations does not support image-to-image editing.',
    );
  }

  String _detectMimeType(String? contentType) {
    if (contentType == null) return 'image/png';
    final first = contentType.split(';').first.trim();
    if (first.startsWith('image/')) return first;
    return 'image/png';
  }
}