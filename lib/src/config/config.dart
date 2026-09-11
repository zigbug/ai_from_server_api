import 'dart:io';

/// Конфигурация сервера, читаемая из переменных окружения.
class Config {
  Config({
    required this.port,
    required this.hfToken,
    required this.dbPath,
    required this.contextWindow,
    required this.summaryThreshold,
    required this.imageModel,
    required this.imageEditModel,
    required this.version,
    required this.commit,
  });

  final int port;
  final String? hfToken;
  final String dbPath;
  final int contextWindow;
  final int summaryThreshold;
  final String imageModel;
  final String imageEditModel;
  final String version;
  final String commit;

  /// Размер скользящего окна сообщений, передаваемых модели.
  static const defaultContextWindow = 20;

  /// Порог сообщений, после которого история сжимается в резюме.
  static const defaultSummaryThreshold = 40;

  static Config fromEnv() {
    return Config(
      port: int.parse(Platform.environment['PORT'] ?? '8080'),
      hfToken: Platform.environment['HF_TOKEN'],
      dbPath: Platform.environment['DB_PATH'] ?? 'data/ai_server.db',
      contextWindow: int.parse(
        Platform.environment['CONTEXT_WINDOW'] ?? '$defaultContextWindow',
      ),
      summaryThreshold: int.parse(
        Platform.environment['SUMMARY_THRESHOLD'] ??
            '$defaultSummaryThreshold',
      ),
      imageModel:
          Platform.environment['IMAGE_MODEL'] ?? 'stabilityai/stable-diffusion-xl-base-1.0',
      imageEditModel: Platform.environment['IMAGE_EDIT_MODEL'] ??
          'black-forest-labs/FLUX.1-Kontext-dev',
      version: Platform.environment['APP_VERSION'] ?? 'dev',
      commit: Platform.environment['APP_COMMIT'] ?? 'unknown',
    );
  }
}