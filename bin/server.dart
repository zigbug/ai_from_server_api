import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

import 'package:ai_from_server_api/src/config/config.dart';
import 'package:ai_from_server_api/src/http/routes.dart';
import 'package:ai_from_server_api/src/models/model_catalog.dart';
import 'package:ai_from_server_api/src/providers/huggingface_provider.dart';
import 'package:ai_from_server_api/src/service/chat_service.dart';
import 'package:ai_from_server_api/src/store/session_store.dart';

Future<void> main(List<String> args) async {
  final config = Config.fromEnv();
  _initLogging();

  // Открываем хранилище сессий.
  final store = SessionStore.open(config.dbPath);

  // Провайдер Hugging Face Inference API.
  final huggingFace = HuggingFaceProvider(config.hfToken);

  // Каталог HF-моделей (динамический, с кэшем).
  final catalog = ModelCatalog();

  final service = ChatService(
    store: store,
    config: config,
    huggingFace: huggingFace,
    catalog: catalog,
  );

  final router = buildRouter(service);

  final pipeline = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final ip = InternetAddress.anyIPv4;
  final server = await serve(pipeline, ip, config.port);
  print('AI Server listening on http://${server.address.address}:${server.port}');
}

void _initLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    stderr.writeln('${record.time.toIso8601String()} [${record.level.name}] ${record.message}');
  });
}