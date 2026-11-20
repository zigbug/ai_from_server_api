import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

import 'package:ai_from_server_api/src/config/config.dart';
import 'package:ai_from_server_api/src/http/routes.dart';
import 'package:ai_from_server_api/src/models/model_catalog.dart';
import 'package:ai_from_server_api/src/providers/groq_provider.dart';
import 'package:ai_from_server_api/src/providers/huggingface_provider.dart';
import 'package:ai_from_server_api/src/providers/openrouter_provider.dart';
import 'package:ai_from_server_api/src/providers/pollinations_provider.dart';
import 'package:ai_from_server_api/src/service/chat_service.dart';
import 'package:ai_from_server_api/src/store/session_store.dart';

Middleware _corsMiddleware() {
  final allowedExact = <String>{'https://905911.ru'};
  return (Handler innerHandler) {
    return (Request request) async {
      final origin = request.headers['origin'];
      final isAllowed = origin != null &&
          (allowedExact.contains(origin) ||
              origin.startsWith('http://localhost:') ||
              origin.startsWith('http://127.0.0.1:'));
      if (request.method == 'OPTIONS') {
        final headers = <String, String>{
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Max-Age': '86400',
        };
        if (isAllowed) headers['Access-Control-Allow-Origin'] = origin!;
        return Response(204, headers: headers);
      }
      final response = await innerHandler(request);
      if (!isAllowed) return response;
      final headers = Map<String, Object>.from(response.headers);
      headers['Access-Control-Allow-Origin'] = origin!;
      return response.change(headers: headers);
    };
  };
}

Future<void> main(List<String> args) async {
  final config = Config.fromEnv();
  _initLogging();

  // Открываем хранилище сессий.
  final store = SessionStore.open(config.dbPath);

  // Провайдер Hugging Face Inference API.
  final huggingFace = HuggingFaceProvider(config.hfToken);

  // Провайдер OpenRouter (free-роутер `openrouter/free` без баланса).
  final openRouter = OpenRouterProvider(config.openRouterApiKey);

  // Провайдер Groq (OpenAI-совместимый, текстовые модели).
  final groq = GroqProvider(config.groqApiKey);

  // Провайдер Pollinations (генерация картинок, бесплатно, без ключа).
  final pollinations = PollinationsImageProvider();

  // Каталог HF-моделей (динамический, с кэшем).
  final catalog = ModelCatalog();

  final service = ChatService(
    store: store,
    config: config,
    huggingFace: huggingFace,
    openRouter: openRouter,
    groq: groq,
    pollinations: pollinations,
    catalog: catalog,
  );

  final router = buildRouter(service);

  final pipeline = Pipeline()
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final ip = InternetAddress.anyIPv4;
  final server = await serve(pipeline, ip, config.port);
  print('AI Server listening on http://${server.address.address}:${server.port}');
}
void _initLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    stderr.writeln("${record.time.toIso8601String()} [${record.level.name}] ${record.message}");
  });
}
