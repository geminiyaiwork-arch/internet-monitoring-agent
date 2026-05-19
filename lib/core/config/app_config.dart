/// Global runtime configuration. Base URL va parametrlar Settings'dan o'zgartiriladi.
class AppConfig {
  AppConfig._();

  static final AppConfig instance = AppConfig._();

  /// Production default; SQLite `settings.base_url` orqali o'zgartiriladi.
  String baseUrl = 'https://e-mmtb.uz/api/v1';

  /// True bo'lsa real tarmoq o'rniga lokal mock javoblar.
  bool useMockApi = false;

  // === Endpoint paths ===
  static const String loginPath = '/agent/login';
  static const String heartbeatPath = '/agent/heartbeat';
  static const String inventoryPath = '/agent/inventory';
  static const String processesPath = '/agent/processes';
  static const String speedTestPath = '/agent/speed-test';
  static const String logsPath = '/agent/logs';
  static const String commandsPath = '/agent/commands';

  // === Default intervals ===
  static const Duration defaultHeartbeatInterval = Duration(minutes: 5);
  static const Duration defaultSpeedTestInterval = Duration(minutes: 30);
  static const Duration defaultInventoryInterval = Duration(hours: 24);
  static const Duration defaultProcessInterval = Duration(minutes: 5);
  static const Duration defaultCommandsPollInterval = Duration(minutes: 1);

  /// Heartbeat va boshqa joylarda dispatch (15s ichida bir karra tick).
  static const Duration schedulerTick = Duration(seconds: 15);

  static const String appName = 'Internet Monitoring Agent';
  static const String agentKeyHeader = 'X-Agent-Key';

  /// Speed test uchun standart fayl o'lchami (server e'lon qilmasa).
  static const int speedTestDefaultBytes = 5 * 1024 * 1024;

  /// Queue va log saqlanish chegaralari.
  static const int maxSyncQueueRows = 500;
  static const int maxLogRows = 2000;
  static const int logRetentionDays = 30;
}
