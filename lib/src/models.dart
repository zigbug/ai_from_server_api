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
  });

  final String id;
  final String name;
  final ModelKind kind;
  final String provider;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'provider': provider,
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

/// Список доступных моделей (белый список), которые можно выбрать.
final List<ModelInfo> availableModels = [
  // --- Текстовые модели (OpenRouter free tier) ---
  ModelInfo(
    id: 'meta-llama/llama-3.3-70b-instruct',
    name: 'Llama 3.3 70B Instruct',
    kind: ModelKind.text,
    provider: 'openrouter',
  ),
  ModelInfo(
    id: 'deepseek/deepseek-chat-v3-0324',
    name: 'DeepSeek V3 0324',
    kind: ModelKind.text,
    provider: 'openrouter',
  ),
  ModelInfo(
    id: 'qwen/qwen-2.5-72b-instruct',
    name: 'Qwen 2.5 72B Instruct',
    kind: ModelKind.text,
    provider: 'openrouter',
  ),
  ModelInfo(
    id: 'mistralai/mistral-7b-instruct',
    name: 'Mistral 7B Instruct',
    kind: ModelKind.text,
    provider: 'openrouter',
  ),
  // --- Текстовые модели (Hugging Face) ---
  ModelInfo(
    id: 'HuggingFaceH4/zephyr-7b-beta',
    name: 'Zephyr 7B Beta (HF)',
    kind: ModelKind.text,
    provider: 'openrouter',
  ),
  // --- Картинки (Hugging Face) ---
  ModelInfo(
    id: 'stabilityai/stable-diffusion-xl-base-1.0',
    name: 'Stable Diffusion XL',
    kind: ModelKind.image,
    provider: 'huggingface',
  ),
  ModelInfo(
    id: 'black-forest-labs/FLUX.1-schnell',
    name: 'FLUX.1 Schnell',
    kind: ModelKind.image,
    provider: 'huggingface',
  ),
  ModelInfo(
    id: 'stabilityai/stable-diffusion-3-medium-diffusers',
    name: 'Stable Diffusion 3 Medium',
    kind: ModelKind.image,
    provider: 'huggingface',
  ),
  // --- Редактирование картинок (image-to-image, Hugging Face) ---
  ModelInfo(
    id: 'black-forest-labs/FLUX.1-Kontext-dev',
    name: 'FLUX.1 Kontext Dev (edit)',
    kind: ModelKind.edit,
    provider: 'huggingface',
  ),
  ModelInfo(
    id: 'Qwen/Qwen-Image-Edit',
    name: 'Qwen Image Edit',
    kind: ModelKind.edit,
    provider: 'huggingface',
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
