import 'dart:convert';
import 'dart:io';

import '../models/provider_config.dart';

/// Result of forwarding a request to a single provider.
class RouteResult {
  final ProviderConfig provider;
  final int statusCode;
  final Map<String, dynamic>? body;
  final String? errorMessage;

  RouteResult({
    required this.provider,
    required this.statusCode,
    this.body,
    this.errorMessage,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isQuotaError =>
      statusCode == 401 || statusCode == 403 || statusCode == 429;
}

/// Routes API requests to upstream providers with automatic failover.
///
/// Maintains a priority-sorted list of providers. When a request fails
/// with a quota-related error (401/403/429) or a connection error, the
/// provider is marked as [ProviderStatus.quotaExhausted] and the next
/// available provider is tried automatically.
class ProviderRouter {
  final List<ProviderConfig> _providers;

  /// Per-provider status overrides (set when a provider is exhausted at
  /// runtime, independent of the persisted config).
  final Map<String, ProviderStatus> _statusOverrides = {};

  ProviderRouter(this._providers);

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /// Replace the internal provider list (called when config changes).
  void updateProviders(List<ProviderConfig> providers) {
    _providers
      ..clear()
      ..addAll(providers);
  }

  /// Return providers that are currently available for routing, sorted
  /// by priority (highest first).
  List<ProviderConfig> getAvailableProviders() {
    final sorted = List<ProviderConfig>.from(_providers)
      ..sort((a, b) => b.priority.compareTo(a.priority));

    return sorted.where((p) {
      final status = _statusOverrides[p.id] ?? p.status;
      return status == ProviderStatus.active &&
          p.apiKey != null &&
          p.apiKey!.isNotEmpty;
    }).toList();
  }

  /// Re-enable a provider that was previously marked as exhausted or
  /// errored at runtime.
  void resetProvider(String providerId) {
    _statusOverrides.remove(providerId);
  }

  /// Route a request to an available provider with auto-failover.
  ///
  /// Tries each available provider in priority order. If a provider
  /// returns [isQuotaError] or throws a connection error it is marked
  /// as quotaExhausted and the next one is tried. On success
  /// [onResponse] is called with the parsed JSON body. On final
  /// failure (all providers tried) [onError] is called with a summary.
  Future<void> routeRequest(
    String model,
    Map<String, dynamic> body, {
    required void Function(Map<String, dynamic>) onResponse,
    required void Function(String) onError,
  }) async {
    final providers = getAvailableProviders();

    if (providers.isEmpty) {
      onError('No available providers (all exhausted or missing API keys)');
      return;
    }

    String? lastError;

    for (final provider in providers) {
      try {
        final result = await _forwardRequest(provider, model, body);

        if (result.isSuccess) {
          // Successful call – increment usage and return.
          provider.incrementUsage();
          if (result.body != null) {
            onResponse(result.body!);
          } else {
            onError('Empty response from ${provider.name}');
          }
          return;
        }

        // Capture the error for the fallback message.
        lastError = '${provider.name}: ${result.errorMessage ?? "HTTP ${result.statusCode}"}';

        if (result.isQuotaError) {
          _statusOverrides[provider.id] = ProviderStatus.quotaExhausted;
        }
        // Non-quota server errors (5xx, 4xx other than 401/403/429)
        // are not automatically fatal – we still try the next provider
        // but do NOT mark the provider as exhausted so it may be
        // retried later.
      } catch (e) {
        lastError = '${provider.name}: Connection error – $e';
        // Connection/network errors mark the provider as exhausted so
        // we don't keep hammering a down endpoint.
        _statusOverrides[provider.id] = ProviderStatus.quotaExhausted;
      }
    }

    // All providers exhausted.
    onError(lastError ?? 'All providers exhausted');
  }

  /// Forward a single request to a provider using [dart:io] HttpClient.
  Future<RouteResult> _forwardRequest(
    ProviderConfig provider,
    String model,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final url = Uri.parse('${provider.baseUrl}/chat/completions');
      final request = await client.postUrl(url);

      // --- Headers --------------------------------------------------
      request.headers.set('Content-Type', 'application/json');
      if (provider.apiKey != null && provider.apiKey!.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${provider.apiKey}');
      }

      // --- Body -----------------------------------------------------
      body['model'] = model;
      request.write(jsonEncode(body));

      // --- Response -------------------------------------------------
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      Map<String, dynamic>? parsedBody;
      String? errorMsg;

      if (responseBody.isNotEmpty) {
        try {
          parsedBody = jsonDecode(responseBody) as Map<String, dynamic>;
          if (response.statusCode >= 400) {
            errorMsg = parsedBody['error']?['message']?.toString() ??
                parsedBody['error']?.toString() ??
                responseBody;
          }
        } catch (_) {
          // Response body is not valid JSON – treat it as raw error text.
          errorMsg = responseBody;
        }
      }

      return RouteResult(
        provider: provider,
        statusCode: response.statusCode,
        body: parsedBody,
        errorMessage: errorMsg,
      );
    } catch (e) {
      return RouteResult(
        provider: provider,
        statusCode: 0,
        errorMessage: e.toString(),
      );
    } finally {
      client.close();
    }
  }

  // ------------------------------------------------------------------
  // Model → provider matching
  // ------------------------------------------------------------------

  /// Extract the "prefix" of a model name – the first segment before
  /// '-' or '/' – used for matching a requested model to the provider
  /// that can serve it.
  static String modelPrefix(String model) {
    // For models like "nvidia/llama-3.1-nemotron-70b-instruct" we want
    // the segment before the first '/'.
    if (model.contains('/')) {
      return model.split('/').first;
    }
    return model.split('-').first;
  }

  /// Return the first [ProviderConfig] whose model list includes
  /// [model] (either exact match or prefix match).
  ProviderConfig? findProviderForModel(String model) {
    final modelPfx = modelPrefix(model);

    for (final provider in _providers) {
      for (final m in provider.models) {
        if (model == m) return provider;
        if (modelPfx == modelPrefix(m)) return provider;
      }
    }
    return null;
  }
}
