import 'dart:convert';
import 'dart:typed_data';

/// Роль сообщения в диалоге.
enum MessageRole {
  system,
  user,
  assistant;

  static MessageRole fromString(String? s) {
    switch (s) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
      default:
        return MessageRole.system;
    }
  }
}

/// Модель данных для одного сообщения диалога.
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final MessageRole role;
  final String content;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'role': role.name,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Информация о типе модели (текстовая, генерация или редактирование картинок).
enum ModelKind { text, image, edit }

/// Описание доступной модели для выбора в настройках.
class ModelInfo {
  ModelInfo({
    required this.id,
    required this.name,
    required this.kind,
    required this.provider,
    this.free = true,
  });

  final String id;
  final String name;
  final ModelKind kind;
  final String provider;
  final bool free;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'provider': provider,
        'free': free,
      };
}

/// Данные сессии диалога.
class Session {
  Session({
    required this.id,
    required this.name,
    required this.model,
    required this.systemPrompt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String model;
  final String systemPrompt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Session copyWith({String? name, String? model, String? systemPrompt}) {
    return Session(
      id: id,
      name: name ?? this.name,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'model': model,
        'system_prompt': systemPrompt,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// Статический (fallback) список доступных моделей Hugging Face.
/// Используется как запасной вариант при недоступности HF Hub,
/// а также для валидации ID моделей.
final List<ModelInfo> availableModels = [
  // --- Текстовые модели (Groq, OpenAI-совместимый API) ---
  ModelInfo(
    id: 'openai/gpt-oss-20b',
    name: 'GPT OSS 20B',
    kind: ModelKind.text,
    provider: 'groq',
    free: true,
  ),
  ModelInfo(
    id: 'openai/gpt-oss-120b',
    name: 'GPT OSS 120B',
    kind: ModelKind.text,
    provider: 'groq',
    free: true,
  ),
  ModelInfo(
    id: 'qwen/qwen3-32b',
    name: 'Qwen3 32B',
    kind: ModelKind.text,
    provider: 'groq',
    free: true,
  ),
  ModelInfo(
    id: 'groq/compound',
    name: 'Groq Compound',
    kind: ModelKind.text,
    provider: 'groq',
    free: true,
  ),
  ModelInfo(
    id: 'groq/compound-mini',
    name: 'Groq Compound Mini',
    kind: ModelKind.text,
    provider: 'groq',
    free: true,
  ),
  // --- Текстовые модели (OpenRouter free, без баланса) ---
  ModelInfo(
    id: 'openrouter/free',
    name: 'OpenRouter Free (автовыбор)',
    kind: ModelKind.text,
    provider: 'openrouter',
    free: true,
  ),
  // --- Текстовые модели (Hugging Face) ---
  ModelInfo(
    id: 'HuggingFaceH4/zephyr-7b-beta',
    name: 'Zephyr 7B Beta',
    kind: ModelKind.text,
    provider: 'huggingface',
    free: true,
  ),
  ModelInfo(
    id: 'mistralai/Mistral-7B-Instruct-v0.3',
    name: 'Mistral 7B Instruct v0.3',
    kind: ModelKind.text,
    provider: 'huggingface',
    free: true,
  ),
  ModelInfo(
    id: 'Qwen/Qwen2.5-7B-Instruct',
    name: 'Qwen 2.5 7B Instruct',
    kind: ModelKind.text,
    provider: 'huggingface',
    free: true,
  ),
  // --- Картинки (Hugging Face) ---
  ModelInfo(
    id: 'stabilityai/stable-diffusion-xl-base-1.0',
    name: 'Stable Diffusion XL',
    kind: ModelKind.image,
    provider: 'huggingface',
    free: true,
  ),
  ModelInfo(
    id: 'black-forest-labs/FLUX.1-schnell',
    name: 'FLUX.1 Schnell',
    kind: ModelKind.image,
    provider: 'huggingface',
    free: false,
  ),
  ModelInfo(
    id: 'stabilityai/stable-diffusion-3-medium-diffusers',
    name: 'Stable Diffusion 3 Medium',
    kind: ModelKind.image,
    provider: 'huggingface',
    free: true,
  ),
  // --- Редактирование картинок (image-to-image, Hugging Face) ---
  ModelInfo(
    id: 'black-forest-labs/FLUX.1-Kontext-dev',
    name: 'FLUX.1 Kontext Dev (edit)',
    kind: ModelKind.edit,
    provider: 'huggingface',
    free: false,
  ),
  ModelInfo(
    id: 'Qwen/Qwen-Image-Edit',
    name: 'Qwen Image Edit',
    kind: ModelKind.edit,
    provider: 'huggingface',
    free: true,
  ),
];

/// Найти модель по ID. Возвращает null, если не найдена.
ModelInfo? findModelById(String id) {
  for (final m in availableModels) {
    if (m.id == id) return m;
  }
  return null;
}

/// Декодировать base64 строку в данные.
Uint8List base64DecodeBytes(String s) {
  return base64.decode(s);
}
