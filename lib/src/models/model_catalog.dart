import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Динамический каталог моделей Hugging Face по категориям.
///
/// Для каждого [ModelKind] опрашивает HF Hub API с фильтром по pipeline_tag,
/// кэширует результат на [ttl]. Если Hub недоступен — возвращает статический
/// fallback-список, чтобы `/models` всегда отвечал.
///
/// Флаг `free` определяется по полю `gated`: если модель gated, она считается
/// платной (требует PRO-подписки или согласия на доступ).
class ModelCatalog {
  ModelCatalog({
    http.Client? client,
    this.ttl = const Duration(hours: 1),
    this.limit = 50,
  })  : _clientOurs = client == null,
        _client = client ?? http.Client();

  static const hubUrl = 'https://huggingface.co/api/models';

  static const Map<ModelKind, String> _pipelineByKind = {
    ModelKind.text: 'text-generation',
    ModelKind.image: 'text-to-image',
    ModelKind.edit: 'image-to-image',
  };

  final http.Client _client;
  final bool _clientOurs;
  final Duration ttl;
  final int limit;

  final Map<ModelKind, List<ModelInfo>> _cache = {};
  final Map<ModelKind, DateTime> _fetchedAt = {};

  /// Список моделей для заданной категории.
  /// При пустом кэше или истёкшем TTL опрашивает HF Hub.
  Future<List<ModelInfo>> modelsOfKind(ModelKind kind) async {
    if (!_isStale(kind)) {
      return _cache[kind]!;
    }

    try {
      final fetched = await _fetchModels(kind);
      if (fetched.isNotEmpty) {
        _cache[kind] = fetched;
        _fetchedAt[kind] = DateTime.now();
      }
    } on Exception {
      // Сеть недоступна — используем кэш/fallback.
    }

    if (_cache[kind] == null) {
      _cache[kind] = _fallbackByKind(kind);
      _fetchedAt[kind] = DateTime.now();
    }

    return _cache[kind]!;
  }

  /// Найти текстовую модель по ID. Проверяет динамический каталог,
  /// затем статический fallback.
  Future<ModelInfo?> findTextModel(String id) async {
    for (final m in await modelsOfKind(ModelKind.text)) {
      if (m.id == id) return m;
    }
    return findModelById(id);
  }

  /// Сбросить кэш (при `?refresh=1` на `/models`).
  void invalidate() {
    _cache.clear();
    _fetchedAt.clear();
  }

  bool _isStale(ModelKind kind) {
    final at = _fetchedAt[kind];
    return at == null || DateTime.now().difference(at) > ttl;
  }

  void close() {
    if (_clientOurs) _client.close();
  }

  Future<List<ModelInfo>> _fetchModels(ModelKind kind) async {
    final uri = Uri.parse(hubUrl).replace(queryParameters: {
      'pipeline_tag': _pipelineByKind[kind]!,
      'sort': 'downloads',
      'direction': '-1',
      'limit': '$limit',
      'full': 'true',
    });

    final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('HF Hub error ${resp.statusCode}');
    }

    final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
    final models = <ModelInfo>[];
    for (final e in list) {
      final map = e as Map<String, dynamic>;
      final tags = (map['tags'] as List? ?? []).cast<String>();
      // GGUF-квантизации не работают через serverless Inference API.
      if (tags.contains('gguf')) continue;
      if (map['pipeline_tag'] != _pipelineByKind[kind]) continue;
      final id = map['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final gated = _isGated(map['gated']);
      models.add(
        ModelInfo(
          id: id,
          name: _prettyName(id),
          kind: kind,
          provider: 'huggingface',
          free: !gated,
        ),
      );
    }
    return models;
  }

  /// Определить, является ли модель gated (требует согласия / PRO).
  static bool _isGated(Object? raw) {
    if (raw == null) return false;
    if (raw is bool) return raw;
    if (raw is String) return raw.isNotEmpty && raw.toLowerCase() != 'false';
    return true;
  }

  static List<ModelInfo> _fallbackByKind(ModelKind kind) {
    return availableModels.where((m) => m.kind == kind).toList();
  }

  static String _prettyName(String id) {
    final short = id.contains('/') ? id.split('/').last : id;
    return short
        .split('-')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }
}
