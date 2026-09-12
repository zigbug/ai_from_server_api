import 'dart:io';

import 'package:sqlite3/sqlite3.dart' hide Session;
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Хранилище сессий и истории сообщений на базе SQLite.
class SessionStore {
  SessionStore._(this._db, this.dbPath);

  final Database _db;
  final String dbPath;
  static final _uuid = const Uuid();

  /// Открыть (создать при необходимости) базу данных.
  factory SessionStore.open(String dbPath) {
    // Убедиться, что каталог для БД существует.
    final dir = File(dbPath).parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode = WAL;');
    final store = SessionStore._(db, dbPath);
    store._init();
    return store;
  }

  void _init() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        model TEXT NOT NULL,
        system_prompt TEXT NOT NULL DEFAULT '',
        provider TEXT,
        summary TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      );
    ''');
    // Индекс для быстрой выборки истории по сессии.
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_session
      ON messages (session_id, id);
    ''');

    _migrate();
  }

  /// Миграции схемы для уже существующих баз.
  void _migrate() {
    // v2: колонка provider в sessions (явный выбор провайдера).
    final columns = _db
        .select('PRAGMA table_info(sessions)')
        .map((r) => r['name'] as String)
        .toSet();
    if (!columns.contains('provider')) {
      _db.execute("ALTER TABLE sessions ADD COLUMN provider TEXT");
    }
  }

  /// Создать новую сессию.
  Session createSession({
    required String name,
    required String model,
    required String systemPrompt,
    String? provider,
  }) {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      'INSERT INTO sessions (id, name, model, system_prompt, provider, summary, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [id, name, model, systemPrompt, provider, '', now, now],
    );
    return Session(
      id: id,
      name: name,
      model: model,
      systemPrompt: systemPrompt,
      provider: provider,
    );
  }

  /// Получить сессию по ID или null.
  Session? getSession(String id) {
    final rows = _db.select(
      'SELECT * FROM sessions WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  /// Список всех сессий (без истории).
  List<Session> listSessions() {
    final rows = _db.select('SELECT * FROM sessions ORDER BY updated_at DESC');
    return rows.map(_sessionFromRow).toList();
  }

  Session _sessionFromRow(Row row) {
    return Session(
      id: row['id'] as String,
      name: row['name'] as String,
      model: row['model'] as String,
      systemPrompt: row['system_prompt'] as String,
      provider: row['provider'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// Обновить данные сессии (имя, модель, системный промт, провайдер).
  Session updateSession({
    required String id,
    String? name,
    String? model,
    String? systemPrompt,
    String? provider,
  }) {
    final existing = getSession(id);
    if (existing == null) {
      throw StateError('Session not found: $id');
    }
    final updated = existing.copyWith(
      name: name,
      model: model,
      systemPrompt: systemPrompt,
      provider: provider,
    );
    _db.execute(
      'UPDATE sessions SET name = ?, model = ?, system_prompt = ?, provider = ?, updated_at = ? WHERE id = ?',
      [
        updated.name,
        updated.model,
        updated.systemPrompt,
        updated.provider,
        updated.updatedAt.toUtc().toIso8601String(),
        id,
      ],
    );
    return updated;
  }

  /// Удалить сессию и её историю.
  bool deleteSession(String id) {
    _db.execute('DELETE FROM messages WHERE session_id = ?', [id]);
    _db.execute('DELETE FROM sessions WHERE id = ?', [id]);
    return getSession(id) == null;
  }

  /// Добавить сообщение в историю сессии.
  void addMessage({required String sessionId, required ChatMessage message}) {
    _db.execute(
      'INSERT INTO messages (session_id, role, content, created_at) '
      'VALUES (?, ?, ?, ?)',
      [
        sessionId,
        message.role.name,
        message.content,
        message.createdAt.toUtc().toIso8601String(),
      ],
    );
    _db.execute(
      'UPDATE sessions SET updated_at = ? WHERE id = ?',
      [DateTime.now().toUtc().toIso8601String(), sessionId],
    );
  }

  /// Получить историю сообщений сессии (в хронологическом порядке).
  List<ChatMessage> getHistory(String sessionId) {
    final rows = _db.select(
      'SELECT * FROM messages WHERE session_id = ? ORDER BY id ASC',
      [sessionId],
    );
    return rows
        .map((row) => ChatMessage(
              role: MessageRole.fromString(row['role'] as String?),
              content: row['content'] as String,
              createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            ))
        .toList();
  }

  /// Количество сообщений в истории сессии.
  int messageCount(String sessionId) {
    final rows = _db.select(
      'SELECT COUNT(*) AS c FROM messages WHERE session_id = ?',
      [sessionId],
    );
    return rows.first['c'] as int;
  }

  /// Сохранить (или обновить) резюме сессии.
  void setSummary(String sessionId, String summary) {
    _db.execute(
      'UPDATE sessions SET summary = ?, updated_at = ? WHERE id = ?',
      [
        summary,
        DateTime.now().toUtc().toIso8601String(),
        sessionId,
      ],
    );
  }

  /// Получить резюме сессии (пустую строку, если нет).
  String getSummary(String sessionId) {
    final rows = _db.select(
      'SELECT summary FROM sessions WHERE id = ?',
      [sessionId],
    );
    if (rows.isEmpty) return '';
    return rows.first['summary'] as String;
  }

  /// Сжать историю: оставить последние [keepLast] сообщений, а более старые
  /// вернуть отдельно (для резюмирования).
  ///
  /// Возвращает (старые сообщения, новые сообщения).
  (List<ChatMessage>, List<ChatMessage>) splitHistory(
    String sessionId, {
    required int keepLast,
  }) {
    final all = getHistory(sessionId);
    if (all.length <= keepLast) {
      return (const [], all);
    }
    final splitAt = all.length - keepLast;
    return (all.sublist(0, splitAt), all.sublist(splitAt));
  }

  /// Удалить самые старые сообщения, оставив последние [keepLast].
  void trimHistory(String sessionId, {required int keepLast}) {
    final all = getHistory(sessionId);
    if (all.length <= keepLast) return;
    final toRemove = all.length - keepLast;
    _db.execute(
      '''
      DELETE FROM messages
      WHERE session_id = ? AND id IN (
        SELECT id FROM messages WHERE session_id = ?
        ORDER BY id ASC LIMIT ?
      )
      ''',
      [sessionId, sessionId, toRemove],
    );
  }

  /// Получить последние [n] сообщений (в хронологическом порядке).
  List<ChatMessage> getLastMessages(String sessionId, {required int n}) {
    final all = getHistory(sessionId);
    if (all.length <= n) return all;
    return all.sublist(all.length - n);
  }

  /// Закрыть соединение с БД.
  void close() {
    _db.dispose();
  }
}
