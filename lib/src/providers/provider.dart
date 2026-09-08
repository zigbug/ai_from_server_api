import 'dart:typed_data';

import '../models.dart';

/// Результат текстовой генерации.
class TextResult {
  TextResult({required this.text, required this.provider});
  final String text;
  final String provider;
}

/// Результат генерации изображения.
class ImageResult {
  ImageResult({required this.bytes, required this.mimeType, required this.provider});
  final Uint8List bytes;
  final String mimeType;
  final String provider;
}

/// Единый интерфейс для вызова моделей (текст и изображения).
abstract class LLMProvider {
  /// Генерировать текстовый ответ на основе сообщений чата.
  /// [systemPrompt] — системный промт.
  Future<TextResult> chat({
    required List<ChatMessage> messages,
    required String model,
    String? systemPrompt,
  });

  /// Сократить историю диалога до краткого резюме (для сжатия контекста).
  Future<String> summarize({
    required List<ChatMessage> messages,
    required String model,
  });
}

/// Провайдер, умеющий генерировать и редактировать изображения.
abstract class ImageProvider {
  Future<ImageResult> generateImage({
    required String prompt,
    required String model,
  });

  /// Image-to-image: взять входное изображение и применить к нему промт.
  Future<ImageResult> editImage({
    required String prompt,
    required Uint8List image,
    required String model,
    String? negativePrompt,
    double? guidanceScale,
    int? numInferenceSteps,
    int? width,
    int? height,
  });
}
