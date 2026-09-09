import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../models.dart';
import '../service/chat_service.dart';
import 'helpers.dart';

/// Создание маршрутов приложения.
Router buildRouter(ChatService service) {
  final router = Router()
    ..get('/', (req) => _rootHandler(req, service))
    ..get('/health', (req) => _healthHandler(req, service))
    ..get('/models', (req) => _modelsHandler(req, service))
    ..post('/images', (req) => _imagesHandler(req, service))
    ..post('/images/edit', (req) => _imagesEditHandler(req, service))
    ..post('/sessions', (req) => _createSession(req, service))
    ..get('/sessions', (req) => _listSessions(req, service))
    ..get('/sessions/<id>', (req, id) => _getSession(req, service, id))
    ..patch('/sessions/<id>', (req, id) => _updateSession(req, service, id))
    ..delete('/sessions/<id>', (req, id) => _deleteSession(req, service, id))
    ..get('/sessions/<id>/history', (req, id) => _sessionHistory(req, service, id))
    ..post('/sessions/<id>/messages', (req, id) => _sendMessage(req, service, id));

  return router;
}

Response _rootHandler(Request req, ChatService service) {
  return Response.ok(
    jsonEncode({
      'name': 'AI Server API',
      'version': service.config.version,
      'endpoints': ['/health', '/models', '/images', '/sessions', '/sessions/<id>/messages'],
    }),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Response _healthHandler(Request req, ChatService service) {
  return jsonResponse({
    'status': 'ok',
    'version': service.config.version,
    'time': DateTime.now().toUtc().toIso8601String(),
    'sessions': service.store.listSessions().length,
  });
}

Future<Response> _modelsHandler(Request req, ChatService service) async {
  return jsonResponse({
    'text': (await service.textModels())
        .map((m) => m.toJson())
        .toList(),
    'image': availableModels
        .where((m) => m.kind == ModelKind.image)
        .map((m) => m.toJson())
        .toList(),
    'edit': availableModels
        .where((m) => m.kind == ModelKind.edit)
        .map((m) => m.toJson())
        .toList(),
  });
}

Future<Response> _imagesHandler(Request req, ChatService service) async {
  try {
    final body = await _readBody(req);
    final prompt = body['prompt'] as String?;
    final model = body['model'] as String? ?? service.config.imageModel;
    if (prompt == null || prompt.trim().isEmpty) {
      return jsonResponse({'error': 'prompt is required'}, statusCode: 400);
    }
    final result = await service.generateImage(prompt: prompt, model: model);
    return jsonResponse({
      'image': base64Encode(result.bytes),
      'mime_type': result.mimeType,
      'prompt': prompt,
      'model': model,
    });
  } catch (e) {
    return failure(e);
  }
}

Future<Response> _imagesEditHandler(Request req, ChatService service) async {
  try {
    final body = await _readBody(req);
    final prompt = body['prompt'] as String?;
    final imageB64 = body['image'] as String?;
    final model = body['model'] as String? ?? service.config.imageEditModel;
    if (prompt == null || prompt.trim().isEmpty) {
      return jsonResponse({'error': 'prompt is required'}, statusCode: 400);
    }
    if (imageB64 == null || imageB64.trim().isEmpty) {
      return jsonResponse({'error': 'image (base64) is required'}, statusCode: 400);
    }
    final Uint8List image;
    try {
      image = base64Decode(imageB64);
    } on FormatException {
      return jsonResponse({'error': 'image is not valid base64'}, statusCode: 400);
    }

    final result = await service.editImage(
      prompt: prompt,
      image: image,
      model: model,
      negativePrompt: body['negative_prompt'] as String?,
      guidanceScale: (body['guidance_scale'] as num?)?.toDouble(),
      numInferenceSteps: (body['num_inference_steps'] as num?)?.toInt(),
      width: (body['width'] as num?)?.toInt(),
      height: (body['height'] as num?)?.toInt(),
    );
    return jsonResponse({
      'image': base64Encode(result.bytes),
      'mime_type': result.mimeType,
      'prompt': prompt,
      'model': model,
    });
  } catch (e) {
    return failure(e);
  }
}

Future<Response> _createSession(Request req, ChatService service) async {
  try {
    final body = await _readBody(req);
    final name = (body['name'] as String? ?? 'New session').trim();
    final model = (body['model'] as String? ?? await service.defaultTextModelId()).trim();
    final systemPrompt = (body['system_prompt'] as String? ?? '').trim();
    final session = service.createSession(
      name: name,
      model: model,
      systemPrompt: systemPrompt,
    );
    return jsonResponse(session.toJson(), statusCode: 201);
  } catch (e) {
    return failure(e);
  }
}

Response _listSessions(Request req, ChatService service) {
  final sessions = service.store.listSessions();
  return jsonResponse({'sessions': sessions.map((s) => s.toJson()).toList()});
}

Response _getSession(Request req, ChatService service, String id) {
  final session = service.store.getSession(id);
  if (session == null) {
    return jsonResponse({'error': 'Session not found'}, statusCode: 404);
  }
  return jsonResponse(session.toJson());
}

Future<Response> _updateSession(Request req, ChatService service, String id) async {
  try {
    final body = await _readBody(req);
    final session = service.store.updateSession(
      id: id,
      name: body['name'] as String?,
      model: body['model'] as String?,
      systemPrompt: body['system_prompt'] as String?,
    );
    return jsonResponse(session.toJson());
  } catch (e) {
    return failure(e);
  }
}

Response _deleteSession(Request req, ChatService service, String id) {
  final deleted = service.store.deleteSession(id);
  if (!deleted) {
    return jsonResponse({'error': 'Session not found'}, statusCode: 404);
  }
  return jsonResponse({'deleted': true});
}

Response _sessionHistory(Request req, ChatService service, String id) {
  final session = service.store.getSession(id);
  if (session == null) {
    return jsonResponse({'error': 'Session not found'}, statusCode: 404);
  }
  final history = service.store.getHistory(id);
  return jsonResponse({
    'session_id': id,
    'summary': service.store.getSummary(id),
    'messages': history.map((m) => m.toJson()).toList(),
  });
}

Future<Response> _sendMessage(
  Request req,
  ChatService service,
  String id,
) async {
  try {
    if (service.store.getSession(id) == null) {
      return jsonResponse({'error': 'Session not found'}, statusCode: 404);
    }
    final body = await _readBody(req);
    final text = (body['message'] as String? ?? '').trim();
    if (text.isEmpty) {
      return jsonResponse({'error': 'message is required'}, statusCode: 400);
    }
    final response = await service.sendMessage(sessionId: id, text: text);
    return jsonResponse({'response': response});
  } catch (e) {
    return failure(e);
  }
}

Future<Map<String, dynamic>> _readBody(Request req) async {
  final raw = await req.readAsString();
  if (raw.trim().isEmpty) return <String, dynamic>{};
  return jsonDecode(raw) as Map<String, dynamic>;
}
