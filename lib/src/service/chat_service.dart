import 'dart:typed_data';

import '../config/config.dart';
import '../models.dart';
import '../models/model_catalog.dart';
import '../providers/huggingface_provider.dart';
import '../providers/openrouter_provider.dart';
import '../providers/provider.dart';
import '../store/session_store.dart';

/// Сервис, координирующий работу с сессиями, контекстом и провайдерами.
/// Модели с provider `huggingface` идут через Hugging Face Inference API,
/// остальные — через OpenRouter (включая free-роутер `openrouter/free`).
class ChatService {
  ChatService({
    required this.store,
    required this.config,
    required this.huggingFace,
    required this.openRouter,
    required this.catalog,
  });

  final SessionStore store;
  final Config config;
  final HuggingFaceProvider huggingFace;
  final OpenRouterProvider openRouter;
  final ModelCatalog catalog;

  /// Создать сессию (проверяет, что модель не image/edit).
  Future<Session> createSession({
    required String name,
    required String model,
    String systemPrompt = '',
  }) async {
    await _validateTextModel(model);
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

    final systemPrompt = _buildSystemPrompt(summary, session.systemPrompt);

    final provider = await _providerForModel(session.model);
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

    final (old, _) = store.splitHistory(
      sessionId,
      keepLast: config.contextWindow,
    );
    if (old.isEmpty) return;

    final existingSummary = store.getSummary(sessionId);
    final toSummarize = <ChatMessage>[];
    if (existingSummary.isNotEmpty) {
      toSummarize.add(
        ChatMessage(role: MessageRole.system, content: 'Previous summary: $existingSummary'),
      );
    }
    toSummarize.addAll(old);

    final newSummary = await (await _providerForModel(model)).summarize(
      messages: toSummarize,
      model: model,
    );
    store.setSummary(sessionId, newSummary);

    store.trimHistory(sessionId, keepLast: config.contextWindow);
  }

  /// Выбрать провайдера по модели: динамические/статичные HF-модели идут
  /// в Hugging Face, всё остальное (включая `openrouter/free`) — в OpenRouter.
  Future<LLMProvider> _providerForModel(String modelId) async {
    final info = await findTextModel(modelId);
    if (info != null && info.provider == 'huggingface') {
      return huggingFace;
    }
    return openRouter;
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

  /// Генерация изображения.
  Future<ImageResult> generateImage({
    required String prompt,
    required String model,
  }) async {
    final imageModels = await catalog.modelsOfKind(ModelKind.image);
    if (!imageModels.any((m) => m.id == model)) {
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
  }) async {
    final editModels = await catalog.modelsOfKind(ModelKind.edit);
    if (!editModels.any((m) => m.id == model)) {
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

  /// Список моделей для заданной категории.
  Future<List<ModelInfo>> modelsOfKind(ModelKind kind) async {
    return catalog.modelsOfKind(kind);
  }

  /// Объединённый список текстовых моделей: статический fallback +
  /// динамические HF-модели из каталога.
  Future<List<ModelInfo>> textModels() async {
    final hf = await catalog.modelsOfKind(ModelKind.text);
    final byId = <String, ModelInfo>{
      for (final m in availableModels.where((m) => m.kind == ModelKind.text))
        m.id: m,
    };
    for (final m in hf) {
      byId[m.id] = m;
    }
    return byId.values.toList();
  }

  /// Найти текстовую модель по ID.
  Future<ModelInfo?> findTextModel(String id) async {
    return catalog.findTextModel(id);
  }

  /// ID текстовой модели по умолчанию (первая из списка).
  Future<String> defaultTextModelId() async {
    final models = await textModels();
    return models.first.id;
  }

  /// Проверить, что модель не image/edit (для сессий чата).
  Future<void> _validateTextModel(String model) async {
    final imageModels = await catalog.modelsOfKind(ModelKind.image);
    if (imageModels.any((m) => m.id == model)) {
      throw ArgumentError('Image model cannot be used for text chat: $model');
    }
    final editModels = await catalog.modelsOfKind(ModelKind.edit);
    if (editModels.any((m) => m.id == model)) {
      throw ArgumentError('Image-edit model cannot be used for text chat: $model');
    }
  }
}
