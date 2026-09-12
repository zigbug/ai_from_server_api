import 'dart:typed_data';

import '../config/config.dart';
import '../models.dart';
import '../models/model_catalog.dart';
import '../providers/groq_provider.dart';
import '../providers/huggingface_provider.dart';
import '../providers/openrouter_provider.dart';
import '../providers/pollinations_provider.dart';
import '../providers/provider.dart';
import '../store/session_store.dart';

/// Сервис, координирующий работу с сессиями, контекстом и провайдерами.
/// Модели с provider `huggingface` идут через Hugging Face Inference API,
/// с provider `groq` — через Groq, остальные — через OpenRouter
/// (включая free-роутер `openrouter/free`). Картинки с provider `pollinations`
/// идут через Pollinations (бесплатно, без ключа).
class ChatService {
  ChatService({
    required this.store,
    required this.config,
    required this.huggingFace,
    required this.openRouter,
    required this.groq,
    required this.pollinations,
    required this.catalog,
  });

  final SessionStore store;
  final Config config;
  final HuggingFaceProvider huggingFace;
  final OpenRouterProvider openRouter;
  final GroqProvider groq;
  final PollinationsImageProvider pollinations;
  final ModelCatalog catalog;

  /// Создать сессию (проверяет, что модель не image/edit).
  Future<Session> createSession({
    required String name,
    required String model,
    String systemPrompt = '',
    String? provider,
  }) async {
    await _validateTextModel(model);
    return store.createSession(
      name: name,
      model: model,
      systemPrompt: systemPrompt,
      provider: _normalizeProvider(provider),
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
    await _manageContext(sessionId, session.model, session.provider);

    // Собираем финальный контекст для модели.
    final history = store.getLastMessages(
      sessionId,
      n: config.contextWindow,
    );
    final summary = store.getSummary(sessionId);

    final systemPrompt = _buildSystemPrompt(summary, session.systemPrompt);

    final provider = await _providerForModel(session.model, session.provider);
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
  Future<void> _manageContext(
    String sessionId,
    String model,
    String? explicitProvider,
  ) async {
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

    final newSummary = await (await _providerForModel(model, explicitProvider))
        .summarize(
          messages: toSummarize,
          model: model,
        );
    store.setSummary(sessionId, newSummary);

    store.trimHistory(sessionId, keepLast: config.contextWindow);
  }

  /// Выбрать провайдера для текстовой модели:
  /// 1) явно заданный [explicitProvider] (groq/openrouter/huggingface);
  /// 2) иначе — по ID модели в каталоге: Groq-модели → Groq,
  ///    Pollinations → Pollinations, остальное (включая неизвестное) → HF.
  Future<LLMProvider> _providerForModel(
    String modelId,
    String? explicitProvider,
  ) async {
    switch (_normalizeProvider(explicitProvider)) {
      case 'groq':
        return groq;
      case 'openrouter':
        return openRouter;
      case 'huggingface':
        return huggingFace;
    }

    final models = await textModels();
    for (final m in models) {
      if (m.id == modelId) {
        switch (m.provider) {
          case 'groq':
            return groq;
          case 'openrouter':
            return openRouter;
          default:
            return huggingFace;
        }
      }
    }
    // Неизвестный ID — по умолчанию Hugging Face.
    return huggingFace;
  }

  static String _prettyModelName(String id) {
    final last = id.split('/').last;
    final cleaned = last
        .split('-')
        .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
    return cleaned.isEmpty ? id : cleaned;
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
    String? provider,
  }) async {
    final available = await imageModels();
    ModelInfo? info;
    for (final m in available) {
      if (m.id == model) {
        info = m;
        break;
      }
    }
    if (info == null) {
      throw ArgumentError('Not an image model: $model');
    }

    final explicit = _normalizeProvider(provider);
    if (explicit != null) {
      return explicit == 'pollinations'
          ? pollinations.generateImage(prompt: prompt, model: model)
          : huggingFace.generateImage(prompt: prompt, model: model);
    }
    if (info.provider == 'pollinations') {
      return pollinations.generateImage(prompt: prompt, model: model);
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
    String? provider,
  }) async {
    final editModels = await catalog.modelsOfKind(ModelKind.edit);
    if (!editModels.any((m) => m.id == model)) {
      throw ArgumentError('Not an image-edit model: $model');
    }

    if ((_normalizeProvider(provider) ?? 'huggingface') == 'pollinations') {
      return pollinations.editImage(
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

  /// Объединённый список моделей генерации изображений: статический
  /// (включая `pollinations/sana`) + динамический HF-каталог.
  Future<List<ModelInfo>> imageModels() async {
    final byId = <String, ModelInfo>{
      for (final m in availableModels.where((m) => m.kind == ModelKind.image))
        m.id: m,
    };
    for (final m in await catalog.modelsOfKind(ModelKind.image)) {
      byId[m.id] = m;
    }
    return byId.values.toList();
  }

  /// Объединённый список текстовых моделей: статический fallback +
  /// динамические HF-модели из каталога + динамические модели Groq.
  /// Groq добавляется последним, чтобы модели с дублирующимися ID
  /// (например, `openai/gpt-oss-20b` на HF Hub и Groq) гарантированно
  /// отправлялись в Groq.
  Future<List<ModelInfo>> textModels() async {
    final byId = <String, ModelInfo>{};

    // Статические текстовые модели (HF и OpenRouter).
    for (final m in availableModels.where((m) => m.kind == ModelKind.text)) {
      if (m.provider == 'groq') {
        // Groq-модели добавляются ниже (после HF), когда есть ключ.
        continue;
      }
      byId[m.id] = m;
    }

    // Динамические HF-модели из каталога (Hub + кэш).
    for (final m in await catalog.modelsOfKind(ModelKind.text)) {
      byId[m.id] = m;
    }

    // Статические + динамические Groq-модели (только при наличии ключа).
    final groqKey = config.groqApiKey;
    if (groqKey != null && groqKey.isNotEmpty) {
      for (final m in availableModels.where(
        (m) => m.kind == ModelKind.text && m.provider == 'groq',
      )) {
        byId[m.id] = m;
      }
      for (final id in await groq.listModels()) {
        if (!byId.containsKey(id)) {
          byId[id] = ModelInfo(
            id: id,
            name: _prettyModelName(id),
            kind: ModelKind.text,
            provider: 'groq',
            free: true,
          );
        }
      }
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

  /// Нормализовать имя провайдера (null/пустая строка → null).
  static String? _normalizeProvider(String? p) {
    if (p == null || p.trim().isEmpty) return null;
    return p.trim().toLowerCase();
  }

  /// Полный сброс кэшей: каталог HF-моделей + кэш маппинга провайдеров.
  /// Списки Groq и Pollinations уже тянутся заново при каждом вызове.
  void invalidateAll() {
    catalog.invalidate();
    huggingFace.invalidateProviderMapping();
  }
}
