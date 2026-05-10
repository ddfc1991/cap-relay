import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/provider_config.dart';
import '../models/provider_list.dart';

/// Service responsible for persisting and loading application configuration.
///
/// Configuration is stored in two places:
/// - A local JSON file (config.json) for the full [AppConfig] state,
///   including provider definitions and settings.
/// - [SharedPreferences] for lightweight per-value lookups such as
///   the active provider index.
class ConfigService {
  static const String _configFileName = 'cap_relay_config.json';
  static const String _activeProviderKey = 'cap_relay_active_provider';
  static const String _apiKeysKey = 'cap_relay_api_keys';

  /// Directory used for persistent file storage.
  final Directory storageDir;

  ConfigService({required this.storageDir});

  // ------------------------------------------------------------------
  // Full config file
  // ------------------------------------------------------------------

  /// Path to the JSON config file.
  String get _configFilePath =>
      '${storageDir.path}/$_configFileName';

  /// Load the full [AppConfig] from disk.
  ///
  /// If the file does not exist, returns a default [AppConfig] seeded
  /// with the built-in provider definitions from [builtInProviders].
  Future<AppConfig> loadConfig() async {
    try {
      final file = File(_configFilePath);
      if (!await file.exists()) {
        return _defaultConfig();
      }

      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        return _defaultConfig();
      }

      final json = jsonDecode(contents) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } catch (e) {
      // On any error (corrupt file, decode failure), fall back to defaults.
      return _defaultConfig();
    }
  }

  /// Save the full [AppConfig] to disk.
  Future<void> saveConfig(AppConfig config) async {
    final file = File(_configFilePath);
    final directory = file.parent;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  /// Return a default [AppConfig] seeded with built-in providers.
  AppConfig _defaultConfig() {
    return AppConfig(
      providers: builtInProviders(),
      serverPort: 8080,
      autoFailover: true,
      currentProviderIndex: 0,
    );
  }

  // ------------------------------------------------------------------
  // API keys (stored separately in SharedPreferences for quick access)
  // ------------------------------------------------------------------

  /// Load all API keys from SharedPreferences.
  ///
  /// Returns a map keyed by provider ID. Entries are only present if
  /// a key has been stored.
  Future<Map<String, String>> loadApiKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_apiKeysKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// Save a single API key for a given provider ID.
  Future<void> saveApiKey(String providerId, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadApiKeys();
    current[providerId] = apiKey;
    await prefs.setString(
      _apiKeysKey,
      jsonEncode(current),
    );
  }

  /// Remove the API key for a given provider ID.
  Future<void> removeApiKey(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadApiKeys();
    current.remove(providerId);
    await prefs.setString(
      _apiKeysKey,
      jsonEncode(current),
    );
  }

  /// Save multiple API keys at once (replaces all stored keys).
  Future<void> saveAllApiKeys(Map<String, String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _apiKeysKey,
      jsonEncode(keys),
    );
  }

  // ------------------------------------------------------------------
  // Active provider (lightweight, stored in SharedPreferences)
  // ------------------------------------------------------------------

  /// Get the index of the currently active provider.
  ///
  /// Returns 0 if no value has been stored.
  Future<int> getActiveProviderIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_activeProviderKey) ?? 0;
  }

  /// Set the index of the currently active provider.
  Future<void> setActiveProviderIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeProviderKey, index);
  }

  /// Convenience: get the [ProviderConfig] that is currently active.
  Future<ProviderConfig?> getActiveProvider() async {
    final config = await loadConfig();
    final index = await getActiveProviderIndex();
    if (index >= 0 && index < config.providers.length) {
      return config.providers[index];
    }
    return null;
  }

  /// Convenience: set the active provider by its [ProviderConfig].
  Future<void> setActiveProvider(ProviderConfig provider) async {
    final config = await loadConfig();
    final index = config.providers.indexWhere((p) => p.id == provider.id);
    if (index >= 0) {
      await setActiveProviderIndex(index);
    }
  }

  // ------------------------------------------------------------------
  // Config migration: sync API keys from SharedPreferences into
  // the ProviderConfig objects before returning.
  // ------------------------------------------------------------------

  /// Load config and inject stored API keys into each provider.
  ///
  /// This is the recommended method for most callers because it keeps
  /// the key store decoupled from the provider config but merges them
  /// at read time.
  Future<AppConfig> loadConfigWithKeys() async {
    final config = await loadConfig();
    final keys = await loadApiKeys();

    for (final provider in config.providers) {
      if (keys.containsKey(provider.id)) {
        provider.apiKey = keys[provider.id];
      }
    }

    return config;
  }
}
