import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Создать JSON-ответ с правильным content-type.
Response jsonResponse(Object? data, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: jsonEncode(data),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// Обработать ошибку как ответ.
Response failure(Object error, {StackTrace? stackTrace}) {
  if (error is! HttpException && error is! ArgumentError && error is! StateError) {
    stderr.writeln('Error: $error');
    if (stackTrace != null) stderr.writeln('$stackTrace');
  }
  return jsonResponse(
    {'error': error.toString()},
    statusCode: 400,
  );
}
