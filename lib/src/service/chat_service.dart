import 'dart:typed_data';

import '../config/config.dart';
import '../models.dart';
import '../providers/huggingface_provider.dart';
import '../providers/provider.dart';
import '../store/session_store.dart';

/// Сервис, координирующий работу с сессиями, контекстом и провайдерами.
class ChatService {
  ChatService({
    required this.store,
    required this.config,
    required this.openRouter,
    required this.huggingFace,
  });

  final SessionStore store;
  final Config config;
  final LLMProvider openRouter;
  final HuggingFaceProvider huggingFace;

  /// Создать сессию.
  Session createSession({
    required String name,
    required String model,
    String systemPrompt = '',
  }) {
    _validateTextModel(model);
    return store.createSession(
      name: name,
      model: model,
      systemPrompt: systemPrompt,
    );
  }

  /// Получить историю сессии как массив сообщений.
  List<ChatMessage> getHistory(String sessionId) {
    return store.getHistory(sessionId);
  }

  /// Отправить сообщение в сессию и получить ответ модели.
  Future<String> sendMessage({
    required String sessionId,
    required String text,
  }) async {
    final session = store.getSession(sessionId);
    if (session == null) {
      throw StateError('Session not found: $sessionId');
    }

    // Сохраняем сообщение пользователя.
    store.addMessage(
      sessionId: sessionId,
      message: ChatMessage(role: MessageRole.user, content: text),
    );

    // Управляем контекстом: при необходимости сжимаем историю в резюме.
    await _manageContext(sessionId, session.model);

    // Собираем финальный контекст для модели.
    final history = store.getLastMessages(
      sessionId,
      n: config.contextWindow,
    );
    final summary = store.getSummary(sessionId);

    // Выбираем провайдера по модели.
    final modelInfo = findModelById(session.model) ??
        ModelInfo(
          id: session.model,
          name: session.model,
          kind: ModelKind.text,
          provider: 'openrouter',
        );

    final LLMProvider provider;
    if (modelInfo.provider == 'huggingface') {
      provider = huggingFace;
    } else {
      provider = openRouter;
    }

    // Формируем системный промт: резюме истории + системный промт сессии.
    final systemPrompt = _buildSystemPrompt(summary, session.systemPrompt);

    final result = await provider.chat(
      messages: history,
      model: session.model,
      systemPrompt: systemPrompt,
    );

    // Сохраняем ответ ассистента.
    store.addMessage(
      sessionId: sessionId,
      message: ChatMessage(role: MessageRole.assistant, content: result.text),
    );

    return result.text;
  }

  /// Управление контекстом: когда сообщений больше порога, старые
  /// сворачиваются в резюме, а из истории удаляются.
  Future<void> _manageContext(String sessionId, String model) async {
    final count = store.messageCount(sessionId);
    if (count <= config.summaryThreshold) {
      return;
    }

    // Разделяем историю: первые (старые) и последние (новые).
    final (old, _) = store.splitHistory(
      sessionId,
      keepLast: config.contextWindow,
    );
    if (old.isEmpty) return;

    // Резюмируем старую часть.
    final existingSummary = store.getSummary(sessionId);
    final toSummarize = <ChatMessage>[];
    if (existingSummary.isNotEmpty) {
      toSummarize.add(
        ChatMessage(role: MessageRole.system, content: 'Previous summary: $existingSummary'),
      );
    }
    toSummarize.addAll(old);

    final provider = _providerForModel(model);
    final newSummary = await provider.summarize(
      messages: toSummarize,
      model: model,
    );
    store.setSummary(sessionId, newSummary);

    // Удаляем отсуммированные старые сообщения.
    store.trimHistory(sessionId, keepLast: config.contextWindow);
  }

  String _buildSystemPrompt(String summary, String sessionPrompt) {
    final parts = <String>[];
    if (summary.isNotEmpty) {
      parts.add('Conversation summary so far:\n$summary');
    }
    if (sessionPrompt.isNotEmpty) {
      parts.add(sessionPrompt);
    }
    return parts.isEmpty ? '' : parts.join('\n\n');
  }

  LLMProvider _providerForModel(String modelId) {
    final info = findModelById(modelId);
    if (info != null && info.provider == 'huggingface') {
      return huggingFace;
    }
    return openRouter;
  }

  /// Генерация изображения.
  Future<ImageResult> generateImage({
    required String prompt,
    required String model,
  }) {
    final info = findModelById(model);
    if (info == null || info.kind != ModelKind.image) {
      throw ArgumentError('Not an image model: $model');
    }
    return huggingFace.generateImage(prompt: prompt, model: model);
  }

  /// Редактирование изображения (image-to-image).
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
    final info = findModelById(model);
    if (info == null || info.kind != ModelKind.edit) {
      throw ArgumentError('Not an image-edit model: $model');
    }
    return huggingFace.editImage(
      prompt: prompt,
      image: image,
      model: model,
      negativePrompt: negativePrompt,
      guidanceScale: guidanceScale,
      numInferenceSteps: numInferenceSteps,
      width: width,
      height: height,
    );
  }

  /// Список моделей по типу.
  List<ModelInfo> modelsOfKind(ModelKind kind) {
    return availableModels.where((m) => m.kind == kind).toList();
  }

  void _validateTextModel(String model) {
    if (findModelById(model)?.kind == ModelKind.image) {
      throw ArgumentError('Image model cannot be used for text chat: $model');
    }
  }
}
