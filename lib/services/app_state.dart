import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/provider_config.dart';
import 'config_service.dart';
import 'provider_router.dart';
import 'proxy_server.dart';

/// Central application state notifier for the CAP Relay UI.
///
/// Owns the [AppConfig], bridges the [ProxyServer] event stream, and
/// exposes all mutable state consumed by the screens.
class AppState extends ChangeNotifier {
  final ConfigService configService;
  final ProviderRouter router;

  late ProxyServer _proxyServer;
  StreamSubscription<ProxyEvent>? _eventSub;

  // ── Mutable state ───────────────────────────────────────────────────

  AppConfig _config = AppConfig();
  bool _serverRunning = false;
  int _requestCount = 0;
  final List<RequestLog> _requestLogs = [];

  // Runtime status overrides (mirrors ProviderRouter._statusOverrides for UI)
  final Map<String, ProviderStatus> _statusOverrides = {};

  // ── Getters ─────────────────────────────────────────────────────────

  AppConfig get config => _config;
  bool get serverRunning => _serverRunning;
  int get requestCount => _requestCount;
  List<RequestLog> get requestLogs => List.unmodifiable(_requestLogs);
  Map<String, ProviderStatus> get statusOverrides =>
      Map.unmodifiable(_statusOverrides);

  List<ProviderConfig> get providers => _config.providers;
  ProviderConfig? get currentProvider => _config.currentProvider;

  // ── Lifecycle ───────────────────────────────────────────────────────

  AppState({
    required this.configService,
    required this.router,
  }) {
    _proxyServer = ProxyServer(router: router);
  }

  /// Must be called after construction to load config and listen to events.
  Future<void> init() async {
    _config = await configService.loadConfigWithKeys();
    router.updateProviders(_config.providers);
    _listenToServerEvents();
    notifyListeners();
  }

  void _listenToServerEvents() {
    _eventSub?.cancel();
    _eventSub = _proxyServer.events.listen(_onProxyEvent);
  }

  void _onProxyEvent(ProxyEvent event) {
    switch (event.type) {
      case ProxyEventType.serverStarted:
        _serverRunning = true;
        notifyListeners();

      case ProxyEventType.serverStopped:
        _serverRunning = false;
        notifyListeners();

      case ProxyEventType.requestStarted:
        final log = RequestLog(
          model: event.data['model'] as String? ?? 'unknown',
          provider: event.data['provider'] as String? ?? 'unknown',
        );
        _requestLogs.insert(0, log);
        notifyListeners();

      case ProxyEventType.requestCompleted:
        _requestCount++;
        // Update the most recent pending log if it matches
        if (_requestLogs.isNotEmpty &&
            _requestLogs.first.statusCode == null) {
          _requestLogs[0] = RequestLog(
            timestamp: _requestLogs.first.timestamp,
            model: _requestLogs.first.model,
            provider: _requestLogs.first.provider,
            statusCode: event.data['statusCode'] as int?,
            duration: event.data['durationMs'] != null
                ? Duration(milliseconds: event.data['durationMs'] as int)
                : null,
          );
        } else {
          // Log from middleware may not have a preceding requestStarted
          _requestLogs.insert(
            0,
            RequestLog(
              model: event.data['model'] as String? ?? 'unknown',
              provider: event.data['provider'] as String? ?? 'unknown',
              statusCode: event.data['statusCode'] as int?,
              duration: event.data['durationMs'] != null
                  ? Duration(milliseconds: event.data['durationMs'] as int)
                  : null,
            ),
          );
        }
        notifyListeners();

      case ProxyEventType.providerSwitched:
        final oldId = event.data['oldProvider'] as String?;
        final newId = event.data['newProvider'] as String?;
        if (oldId != null) {
          _statusOverrides[oldId] = ProviderStatus.quotaExhausted;
        }
        // Try to update currentProviderIndex
        if (newId != null) {
          final idx = _config.providers
              .indexWhere((p) => p.id == newId);
          if (idx >= 0) {
            _config.currentProviderIndex = idx;
          }
        }
        notifyListeners();

      case ProxyEventType.providerExhausted:
        final id = event.data['providerId'] as String?;
        if (id != null) {
          _statusOverrides[id] = ProviderStatus.quotaExhausted;
        }
        notifyListeners();

      case ProxyEventType.error:
        // Optionally add an error log entry
        notifyListeners();
    }
  }

  // ── Server control ──────────────────────────────────────────────────

  Future<void> startServer() async {
    try {
      await _proxyServer.start(_config.serverPort);
      // Event will set _serverRunning via the stream
    } catch (e) {
      // Re-throw so the UI can show a snackbar
      rethrow;
    }
  }

  Future<void> stopServer() async {
    await _proxyServer.stop();
    // Event will set _serverRunning via the stream
  }

  // ── Config mutations ────────────────────────────────────────────────

  Future<void> saveConfig() async {
    await configService.saveConfig(_config);
  }

  /// Toggle a provider's active state.
  Future<void> toggleProvider(String providerId) async {
    final provider = _config.providers.firstWhere((p) => p.id == providerId);
    provider.isActive = !provider.isActive;
    router.updateProviders(_config.providers);
    await saveConfig();
    notifyListeners();
  }

  /// Reset a provider's exhausted/error runtime status.
  Future<void> resetProvider(String providerId) async {
    _statusOverrides.remove(providerId);
    router.resetProvider(providerId);
    notifyListeners();
  }

  /// Reset all exhausted providers (pull-to-refresh action).
  Future<void> resetAllExhausted() async {
    final exhaustedIds =
        _statusOverrides.keys.toList();
    for (final id in exhaustedIds) {
      _statusOverrides.remove(id);
      router.resetProvider(id);
    }
    // Also re-enable any providers marked inactive due to quota
    for (final p in _config.providers) {
      if (p.quotaLimit != null && p.usageCount >= p.quotaLimit!) {
        p.usageCount = 0;
      }
      p.isActive = true;
    }
    router.updateProviders(_config.providers);
    await saveConfig();
    notifyListeners();
  }

  /// Delete a provider from the config.
  Future<void> deleteProvider(String providerId) async {
    _config.providers.removeWhere((p) => p.id == providerId);
    _statusOverrides.remove(providerId);
    router.updateProviders(_config.providers);
    await saveConfig();
    notifyListeners();
  }

  /// Add a new custom provider.
  Future<void> addProvider(ProviderConfig provider) async {
    _config.providers.add(provider);
    router.updateProviders(_config.providers);
    await saveConfig();
    notifyListeners();
  }

  /// Update the API key for a provider.
  Future<void> updateApiKey(String providerId, String apiKey) async {
    final provider = _config.providers.firstWhere((p) => p.id == providerId);
    provider.apiKey = apiKey;
    await configService.saveApiKey(providerId, apiKey);
    notifyListeners();
  }

  /// Update server port.
  Future<void> updatePort(int port) async {
    _config.serverPort = port;
    await saveConfig();
    notifyListeners();
  }

  /// Toggle auto-failover.
  Future<void> toggleAutoFailover() async {
    _config.autoFailover = !_config.autoFailover;
    await saveConfig();
    notifyListeners();
  }

  /// Add a global API key (for reference).
  Future<void> addApiKey(String key) async {
    _config.apiKeys.add(key);
    await saveConfig();
    notifyListeners();
  }

  /// Remove a global API key.
  Future<void> removeApiKey(String key) async {
    _config.apiKeys.remove(key);
    await saveConfig();
    notifyListeners();
  }

  // ── Log management ──────────────────────────────────────────────────

  void clearLogs() {
    _requestLogs.clear();
    _requestCount = 0;
    notifyListeners();
  }

  /// Get the effective status of a provider (runtime override or config status).
  ProviderStatus effectiveStatus(String providerId) {
    return _statusOverrides[providerId] ??
        _config.providers
            .firstWhere((p) => p.id == providerId,
                orElse: () => ProviderConfig(
                    id: providerId, name: providerId, baseUrl: ''))
            .status;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _proxyServer.dispose();
    super.dispose();
  }
}
