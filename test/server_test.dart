import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  final port = '8099';
  final host = 'http://127.0.0.1:$port';
  late Process p;
  final tmpDb = '${Directory.systemTemp.path}/ai_server_test_${DateTime.now().millisecondsSinceEpoch}.db';

  setUp(() async {
    p = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/server.dart'],
      environment: {
        'PORT': port,
        'DB_PATH': tmpDb,
      },
    );
    // Ждём, пока сервер поднимется.
    var ready = false;
    for (var i = 0; i < 20 && !ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        final r = await get(Uri.parse('$host/health'));
        if (r.statusCode == 200) ready = true;
      } catch (_) {}
    }
    if (!ready) throw StateError('Server did not start');
  });

  tearDown(() {
    p.kill();
  });

  test('Health', () async {
    final r = await get(Uri.parse('$host/health'));
    expect(r.statusCode, 200);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['status'], 'ok');
  });

  test('Version', () async {
    final r = await get(Uri.parse('$host/version'));
    expect(r.statusCode, 200);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['name'], 'AI Server API');
    expect(body['version'], isA<String>());
    expect(body['commit'], isA<String>());
  });

  test('Models list', () async {
    final r = await get(Uri.parse('$host/models'));
    expect(r.statusCode, 200);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect((body['text'] as List).isNotEmpty, isTrue);
    expect((body['image'] as List).isNotEmpty, isTrue);
    expect((body['edit'] as List).isNotEmpty, isTrue);
    // Каждая модель имеет флаг `free`.
    final firstText = (body['text'] as List).first as Map;
    expect(firstText['free'], isA<bool>());
    expect(firstText['provider'], 'huggingface');
  });

  test('Image edit validation', () async {
    // Нет промта.
    final noPrompt = await post(
      Uri.parse('$host/images/edit'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'image': 'aGVsbG8='}),
    );
    expect(noPrompt.statusCode, 400);

    // Нет картинки.
    final noImage = await post(
      Uri.parse('$host/images/edit'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'prompt': 'make it red'}),
    );
    expect(noImage.statusCode, 400);

    // Невалидный base64.
    final badB64 = await post(
      Uri.parse('$host/images/edit'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'prompt': 'x', 'image': '!!!not-base64!!!'}),
    );
    expect(badB64.statusCode, 400);
    expect((jsonDecode(badB64.body) as Map)['error'], isA<String>());
  });

  test('Session CRUD + history', () async {
    // Создать сессию.
    final create = await post(
      Uri.parse('$host/sessions'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'name': 'Test session',
        'model': 'Qwen/Qwen2.5-7B-Instruct',
        'system_prompt': 'You are a helpful assistant.',
      }),
    );
    expect(create.statusCode, 201, reason: create.body);
    final session = jsonDecode(create.body) as Map<String, dynamic>;
    final id = session['id'] as String;
    expect(session['name'], 'Test session');

    // Список.
    final list = await get(Uri.parse('$host/sessions'));
    expect(list.statusCode, 200);
    final sessions = (jsonDecode(list.body) as Map)['sessions'] as List;
    expect(sessions.any((s) => (s as Map)['id'] == id), isTrue);

    // Получить по ID.
    final one = await get(Uri.parse('$host/sessions/$id'));
    expect(one.statusCode, 200);
    expect((jsonDecode(one.body) as Map)['id'], id);

    // Обновить.
    final patchResp = await patch(
      Uri.parse('$host/sessions/$id'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'name': 'Renamed'}),
    );
    expect(patchResp.statusCode, 200);
    expect((jsonDecode(patchResp.body) as Map)['name'], 'Renamed');

    // История пустая.
    final history = await get(Uri.parse('$host/sessions/$id/history'));
    expect(history.statusCode, 200);
    expect(((jsonDecode(history.body) as Map)['messages'] as List), isEmpty);

    // Удалить.
    final del = await delete(Uri.parse('$host/sessions/$id'));
    expect(del.statusCode, 200);

    final gone = await get(Uri.parse('$host/sessions/$id'));
    expect(gone.statusCode, 404);
  });

  test('404 on unknown route', () async {
    final r = await get(Uri.parse('$host/foobar'));
    expect(r.statusCode, 404);
  });
}
