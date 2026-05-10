/// Enum representing the current status of an AI provider.
enum ProviderStatus {
  active,
  quotaExhausted,
  error,
}

/// Configuration for a single AI provider (e.g. OpenAI, DeepSeek).
class ProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  String? apiKey;
  final List<String> models;
  bool isActive;
  int priority;
  int usageCount;
  int? quotaLimit;

  ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    List<String>? models,
    this.isActive = true,
    this.priority = 0,
    this.usageCount = 0,
    this.quotaLimit,
  }) : models = models ?? [];

  /// Deserialize from a JSON map.
  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    return ProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String?,
      models: (json['models'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isActive: json['isActive'] as bool? ?? true,
      priority: json['priority'] as int? ?? 0,
      usageCount: json['usageCount'] as int? ?? 0,
      quotaLimit: json['quotaLimit'] as int?,
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'models': models,
      'isActive': isActive,
      'priority': priority,
      'usageCount': usageCount,
      'quotaLimit': quotaLimit,
    };
  }

  /// Returns the current status based on usage vs quota.
  ProviderStatus get status {
    if (!isActive) return ProviderStatus.error;
    if (quotaLimit != null && usageCount >= quotaLimit!) {
      return ProviderStatus.quotaExhausted;
    }
    return ProviderStatus.active;
  }

  /// Increment usage count by one.
  void incrementUsage() {
    usageCount++;
  }

  @override
  String toString() => 'ProviderConfig($name, id=$id, active=$isActive, '
      'usage=$usageCount/${quotaLimit ?? '∞'})';
}

/// A log entry recording a single API request.
class RequestLog {
  final DateTime timestamp;
  final String model;
  final String provider;
  final int? statusCode;
  final Duration? duration;
  final String? responsePreview;

  RequestLog({
    DateTime? timestamp,
    required this.model,
    required this.provider,
    this.statusCode,
    this.duration,
    this.responsePreview,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Deserialize from a JSON map.
  factory RequestLog.fromJson(Map<String, dynamic> json) {
    return RequestLog(
      timestamp: DateTime.parse(json['timestamp'] as String),
      model: json['model'] as String,
      provider: json['provider'] as String,
      statusCode: json['statusCode'] as int?,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      responsePreview: json['responsePreview'] as String?,
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'model': model,
      'provider': provider,
      'statusCode': statusCode,
      'duration': duration?.inMilliseconds,
      'responsePreview': responsePreview,
    };
  }

  @override
  String toString() =>
      'RequestLog($model @ $provider, ${statusCode ?? 'pending'})';
}

/// Top-level application configuration.
class AppConfig {
  final List<ProviderConfig> providers;
  final List<String> apiKeys;
  int serverPort;
  bool autoFailover;
  int currentProviderIndex;

  AppConfig({
    List<ProviderConfig>? providers,
    List<String>? apiKeys,
    this.serverPort = 8080,
    this.autoFailover = true,
    this.currentProviderIndex = 0,
  })  : providers = providers ?? [],
        apiKeys = apiKeys ?? [];

  /// Deserialize from a JSON map.
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      providers: (json['providers'] as List<dynamic>?)
              ?.map((e) =>
                  ProviderConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      apiKeys: (json['apiKeys'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      serverPort: json['serverPort'] as int? ?? 8080,
      autoFailover: json['autoFailover'] as bool? ?? true,
      currentProviderIndex: json['currentProviderIndex'] as int? ?? 0,
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'providers': providers.map((p) => p.toJson()).toList(),
      'apiKeys': apiKeys,
      'serverPort': serverPort,
      'autoFailover': autoFailover,
      'currentProviderIndex': currentProviderIndex,
    };
  }

  /// The currently active provider config, or null if the index is out of range.
  ProviderConfig? get currentProvider {
    if (currentProviderIndex >= 0 && currentProviderIndex < providers.length) {
      return providers[currentProviderIndex];
    }
    return null;
  }

  @override
  String toString() =>
      'AppConfig(providers=${providers.length}, port=$serverPort, '
      'autoFailover=$autoFailover, current=$currentProviderIndex)';
}
