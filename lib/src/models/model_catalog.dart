import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Динамический каталог текстовых моделей Hugging Face.
///
/// Список текстовых моделей получается программно с Hugging Face Hub
/// (`pipeline_tag=text-generation`) и кэшируется на [ttl]. Если Hub
/// недоступен, возвращается кэш или статический fallback, чтобы
/// `/models` всегда отвечал.
class ModelCatalog {
  ModelCatalog({
    http.Client? client,
    this.ttl = const Duration(hours: 1),
    this.limit = 50,
  })  : _clientOurs = client == null,
        _client = client ?? http.Client();

  static const hubUrl = 'https://huggingface.co/api/models';

  final http.Client _client;
  final bool _clientOurs;
  final Duration ttl;
  final int limit;

  List<ModelInfo> _textCache = [];
  DateTime? _fetchedAt;

  /// Список текстовых HF-моделей (топ по загрузкам).
  /// При пустом кэше или истёкшем TTL опрашивает HF Hub.
  Future<List<ModelInfo>> textModels() async {
    if (_textCache.isEmpty || _isStale()) {
      try {
        final fetched = await _fetchTextModels();
        if (fetched.isNotEmpty) {
          _textCache = fetched;
          _fetchedAt = DateTime.now();
        }
      } on Exception {
        // Сеть недоступна — используем кэш/fallback.
      }
      if (_textCache.isEmpty) {
        _textCache = fallbackHfTextModels;
        _fetchedAt = DateTime.now();
      }
    }
    return _textCache;
  }

  Future<List<ModelInfo>> _fetchTextModels() async {
    final uri = Uri.parse(hubUrl).replace(queryParameters: {
      'pipeline_tag': 'text-generation',
      'sort': 'downloads',
      'direction': '-1',
      'limit': '$limit',
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
      if (map['pipeline_tag'] != 'text-generation') continue;
      final id = map['id'] as String?;
      if (id == null || id.isEmpty) continue;
      models.add(
        ModelInfo(
          id: id,
          name: _prettyName(id),
          kind: ModelKind.text,
          provider: 'huggingface',
        ),
      );
    }
    return models;
  }

  /// Найти текстовую модель по ID. Проверяет динамический HF-список,
  /// затем статический список из [findModelById].
  Future<ModelInfo?> findTextModel(String id) async {
    for (final m in await textModels()) {
      if (m.id == id) return m;
    }
    return findModelById(id);
  }

  bool _isStale() =>
      _fetchedAt == null || DateTime.now().difference(_fetchedAt!) > ttl;

  void close() {
    if (_clientOurs) _client.close();
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

/// Статический fallback для текстовых HF-моделей на случай,
/// если HF Hub недоступен.
final List<ModelInfo> fallbackHfTextModels = [
  ModelInfo(
    id: 'HuggingFaceH4/zephyr-7b-beta',
    name: 'Zephyr 7B Beta',
    kind: ModelKind.text,
    provider: 'huggingface',
  ),
  ModelInfo(
    id: 'mistralai/Mistral-7B-Instruct-v0.3',
    name: 'Mistral 7B Instruct v0.3',
    kind: ModelKind.text,
    provider: 'huggingface',
  ),
  ModelInfo(
    id: 'Qwen/Qwen2.5-7B-Instruct',
    name: 'Qwen 2.5 7B Instruct',
    kind: ModelKind.text,
    provider: 'huggingface',
  ),
];