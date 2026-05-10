import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../models/provider_config.dart';
import 'provider_router.dart';

// ---------------------------------------------------------------------------
// Event types emitted by the proxy server for UI updates.
// ---------------------------------------------------------------------------

/// Categories of events the proxy server publishes.
enum ProxyEventType {
  requestStarted,
  requestCompleted,
  providerSwitched,
  providerExhausted,
  error,
  serverStarted,
  serverStopped,
}

/// A single event emitted by [ProxyServer.events].
class ProxyEvent {
  final ProxyEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  ProxyEvent({
    required this.type,
    DateTime? timestamp,
    Map<String, dynamic>? data,
  })  : timestamp = timestamp ?? DateTime.now(),
        data = data ?? {};

  @override
  String toString() => 'ProxyEvent($type)';
}

// ---------------------------------------------------------------------------
// ProxyServer
// ---------------------------------------------------------------------------

/// An HTTP server that proxies OpenAI-compatible API requests to upstream
/// providers with automatic failover.
///
/// Routes:
///   GET  /v1/models             – list all available models
///   POST /v1/chat/completions   – OpenAI-compatible chat completions
///   POST /v1/responses          – Anthropic-compatible (converted internally)
///
/// All upstream communication uses [dart:io] HttpClient. Streaming
/// (`stream: true` in the request body) is supported for OpenAI-formatted
/// chat completions.
class ProxyServer {
  final ProviderRouter _router;

  HttpServer? _server;
  final StreamController<ProxyEvent> _eventController =
      StreamController<ProxyEvent>.broadcast();

  /// Whether the server is currently running.
  bool get isRunning => _server != null;

  /// Listen to proxy lifecycle events (for UI updates).
  Stream<ProxyEvent> get events => _eventController.stream;

  ProxyServer({
    required ProviderRouter router,
  }) : _router = router;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  /// Start the HTTP server on [port].
  Future<void> start(int port) async {
    if (_server != null) {
      await stop();
    }

    final router = Router()
      ..get('/v1/models', _handleModels)
      ..post('/v1/chat/completions', _handleChatCompletions)
      ..post('/v1/responses', _handleResponses);

    // Wrap with a simple logging middleware.
    final handler =
        const shelf.Pipeline().addMiddleware(_logMiddleware()).addHandler(router);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _eventController.add(ProxyEvent(
      type: ProxyEventType.serverStarted,
      data: {'port': port},
    ));
  }

  /// Gracefully stop the server.
  Future<void> stop() async {
    await _server?.close(force: false);
    _server = null;
    _eventController.add(ProxyEvent(type: ProxyEventType.serverStopped));
  }

  /// Dispose resources (call when the app shuts down).
  void dispose() {
    _eventController.close();
  }

  // ------------------------------------------------------------------
  // Middleware
  // ------------------------------------------------------------------

  shelf.Middleware _logMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        final sw = Stopwatch()..start();
        try {
          final response = await innerHandler(request);
          _eventController.add(ProxyEvent(
            type: ProxyEventType.requestCompleted,
            data: {
              'method': request.method,
              'path': request.url.toString(),
              'statusCode': response.statusCode,
              'durationMs': sw.elapsedMilliseconds,
            },
          ));
          return response;
        } catch (e) {
          _eventController.add(ProxyEvent(
            type: ProxyEventType.error,
            data: {
              'method': request.method,
              'path': request.url.toString(),
              'error': e.toString(),
              'durationMs': sw.elapsedMilliseconds,
            },
          ));
          rethrow;
        }
      };
    };
  }

  // ------------------------------------------------------------------
  // GET /v1/models
  // ------------------------------------------------------------------

  Future<shelf.Response> _handleModels(shelf.Request request) async {
    final providers = _router.getAvailableProviders();
    final models = <Map<String, dynamic>>[];

    for (final provider in providers) {
      for (final model in provider.models) {
        models.add({
          'id': model,
          'object': 'model',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'owned_by': provider.id,
        });
      }
    }

    return shelf.Response.ok(
      jsonEncode({
        'object': 'list',
        'data': models,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ------------------------------------------------------------------
  // POST /v1/chat/completions
  // ------------------------------------------------------------------

  Future<shelf.Response> _handleChatCompletions(
      shelf.Request request) async {
    // Parse body
    Map<String, dynamic> body;
    try {
      body = await _parseBody(request);
    } catch (e) {
      return _errorResponse(400, 'Invalid request body: $e');
    }

    final model = body['model'] as String?;
    if (model == null || model.isEmpty) {
      return _errorResponse(400, 'Missing or empty "model" field');
    }

    // Find the provider that can serve this model
    final provider = _router.findProviderForModel(model);
    if (provider == null) {
      return _errorResponse(400,
          'No configured provider can serve model "$model". '
          'Available models: ${_allModelNames().join(', ')}');
    }

    final isStreaming = body['stream'] == true;

    _eventController.add(ProxyEvent(
      type: ProxyEventType.requestStarted,
      data: {
        'model': model,
        'provider': provider.name,
        'streaming': isStreaming,
      },
    ));

    // Forward to the provider
    if (isStreaming) {
      return _forwardStreaming(provider, model, body);
    } else {
      return _forwardNonStreaming(provider, model, body);
    }
  }

  // ------------------------------------------------------------------
  // POST /v1/responses  (Anthropic-compatible endpoint)
  // ------------------------------------------------------------------

  Future<shelf.Response> _handleResponses(shelf.Request request) async {
    // Parse Anthropic-format body
    Map<String, dynamic> body;
    try {
      body = await _parseBody(request);
    } catch (e) {
      return _errorResponse(400, 'Invalid request body: $e');
    }

    final model = body['model'] as String?;
    if (model == null || model.isEmpty) {
      return _errorResponse(400, 'Missing or empty "model" field');
    }

    // Find provider
    final provider = _router.findProviderForModel(model);
    if (provider == null) {
      return _errorResponse(400,
          'No configured provider can serve model "$model".');
    }

    // Convert Anthropic request → OpenAI format
    final openaiBody = _anthropicToOpenAI(body);

    final isStreaming = body['stream'] == true;

    _eventController.add(ProxyEvent(
      type: ProxyEventType.requestStarted,
      data: {
        'model': model,
        'provider': provider.name,
        'streaming': isStreaming,
        'endpoint': '/v1/responses',
      },
    ));

    // For streaming, we forward the OpenAI-format request and convert
    // each SSE chunk back to Anthropic format.
    if (isStreaming) {
      // Wire up streaming conversion.
      return _forwardStreamingAnthropic(provider, model, openaiBody);
    }

    // Non-streaming: forward, then convert response format.
    final completer = Completer<shelf.Response>();

    await _router.routeRequest(
      model,
      openaiBody,
      onResponse: (openaiResponse) {
        final anthropicResponse = _openAIToAnthropic(openaiResponse, model);
        completer.complete(shelf.Response.ok(
          jsonEncode(anthropicResponse),
          headers: {'Content-Type': 'application/json'},
        ));
      },
      onError: (error) {
        completer.complete(_errorResponse(502, error));
      },
    );

    return completer.future;
  }

  // ------------------------------------------------------------------
  // Forwarding helpers (non-streaming)
  // ------------------------------------------------------------------

  /// Forward a request and return the response as a shelf.Response.
  Future<shelf.Response> _forwardNonStreaming(
    ProviderConfig provider,
    String model,
    Map<String, dynamic> body,
  ) async {
    final completer = Completer<shelf.Response>();

    await _router.routeRequest(
      model,
      body,
      onResponse: (responseBody) {
        completer.complete(shelf.Response.ok(
          jsonEncode(responseBody),
          headers: {'Content-Type': 'application/json'},
        ));
      },
      onError: (error) {
        completer.complete(_errorResponse(502, error));
      },
    );

    return completer.future;
  }

  /// Forward a streaming request and return a shelf streaming response.
  Future<shelf.Response> _forwardStreaming(
    ProviderConfig provider,
    String model,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final url = Uri.parse('${provider.baseUrl}/chat/completions');
      final req = await client.postUrl(url);

      req.headers.set('Content-Type', 'application/json');
      if (provider.apiKey != null && provider.apiKey!.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer ${provider.apiKey}');
      }

      body['model'] = model;
      body['stream'] = true;
      req.write(jsonEncode(body));

      final upstreamResponse = await req.close();

      if (upstreamResponse.statusCode >= 400) {
        final errorBody = await upstreamResponse.transform(utf8.decoder).join();
        client.close();
        return _errorResponse(
          upstreamResponse.statusCode,
          'Upstream error: $errorBody',
        );
      }

      // Stream the upstream response body directly to the client.
      // shelf_iO's HttpServer works with dart:io so we can use
      // shelf.Response with a byte stream.
      final byteStream = upstreamResponse
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) => '${line}\n')
          .transform(utf8.encoder);

      provider.incrementUsage();

      return shelf.Response.ok(
        byteStream,
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      );
    } catch (e) {
      client.close();
      return _errorResponse(502, 'Streaming connection failed: $e');
    }
  }

  /// Forward a streaming request and convert each SSE chunk from OpenAI
  /// format to Anthropic format.
  Future<shelf.Response> _forwardStreamingAnthropic(
    ProviderConfig provider,
    String model,
    Map<String, dynamic> openaiBody,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final url = Uri.parse('${provider.baseUrl}/chat/completions');
      final req = await client.postUrl(url);

      req.headers.set('Content-Type', 'application/json');
      if (provider.apiKey != null && provider.apiKey!.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer ${provider.apiKey}');
      }

      openaiBody['model'] = model;
      openaiBody['stream'] = true;
      req.write(jsonEncode(openaiBody));

      final upstreamResponse = await req.close();

      if (upstreamResponse.statusCode >= 400) {
        final errorBody = await upstreamResponse.transform(utf8.decoder).join();
        client.close();
        return _errorResponse(
          upstreamResponse.statusCode,
          'Upstream error: $errorBody',
        );
      }

      // Convert each SSE data line from OpenAI → Anthropic format.
      final anthropicStream = upstreamResponse
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        if (!line.startsWith('data: ')) return '$line\n';
        final payload = line.substring(6).trim();
        if (payload == '[DONE]') {
          return 'data: {"type":"message_stop"}\n\n';
        }
        try {
          final openaiChunk =
              jsonDecode(payload) as Map<String, dynamic>;
          final anthropicChunk =
              _openAIChunkToAnthropic(openaiChunk);
          return 'data: ${jsonEncode(anthropicChunk)}\n\n';
        } catch (_) {
          return '$line\n';
        }
      }).transform(utf8.encoder);

      provider.incrementUsage();

      return shelf.Response.ok(
        anthropicStream,
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Connection': 'keep-alive',
        },
      );
    } catch (e) {
      client.close();
      return _errorResponse(502, 'Streaming connection failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Format conversion helpers
  // ------------------------------------------------------------------

  /// Convert an Anthropic-format request body to OpenAI chat-completions
  /// format.
  Map<String, dynamic> _anthropicToOpenAI(Map<String, dynamic> body) {
    final openai = <String, dynamic>{};

    // Copy scalar parameters that share the same name.
    for (final key in [
      'temperature',
      'top_p',
      'max_tokens',
      'stop',
      'metadata',
      'user',
    ]) {
      if (body.containsKey(key)) openai[key] = body[key];
    }

    // Map `max_tokens` if present (same name in both).
    if (body.containsKey('max_tokens')) {
      openai['max_tokens'] = body['max_tokens'];
    }

    // Messages – "system" may be a top-level field in Anthropic.
    final messages = <Map<String, dynamic>>[];
    if (body.containsKey('system')) {
      messages.add({
        'role': 'system',
        'content': body['system'],
      });
    }
    if (body.containsKey('messages')) {
      for (final msg in (body['messages'] as List<dynamic>)) {
        messages.add(msg as Map<String, dynamic>);
      }
    }
    openai['messages'] = messages;

    // n (Anthropic doesn't support it directly; omit unless set)
    if (body.containsKey('n')) openai['n'] = body['n'];

    return openai;
  }

  /// Convert an OpenAI chat-completions response to Anthropic format.
  Map<String, dynamic> _openAIToAnthropic(
    Map<String, dynamic> openaiResponse,
    String model,
  ) {
    final choices = openaiResponse['choices'] as List<dynamic>?;
    final firstChoice =
        (choices != null && choices.isNotEmpty)
            ? choices[0] as Map<String, dynamic>
            : <String, dynamic>{};
    final message = firstChoice['message'] as Map<String, dynamic>? ?? {};
    final content = message['content'] as String? ?? '';
    final stopReason = firstChoice['finish_reason'] as String? ?? 'stop';

    // Map finish_reason
    String anthropicStopReason;
    switch (stopReason) {
      case 'stop':
        anthropicStopReason = 'end_turn';
      case 'length':
        anthropicStopReason = 'max_tokens';
      case 'content_filter':
        anthropicStopReason = 'content_filter';
      default:
        anthropicStopReason = stopReason;
    }

    // Map usage
    final usage = openaiResponse['usage'] as Map<String, dynamic>?;
    Map<String, dynamic>? anthropicUsage;
    if (usage != null) {
      anthropicUsage = {
        'input_tokens': usage['prompt_tokens'] ?? 0,
        'output_tokens': usage['completion_tokens'] ?? 0,
      };
    }

    return {
      'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'message',
      'role': 'assistant',
      'content': [
        {
          'type': 'text',
          'text': content,
        }
      ],
      'model': model,
      'stop_reason': anthropicStopReason,
      'stop_sequence': firstChoice['stop_sequence'],
      'usage': anthropicUsage ?? {'input_tokens': 0, 'output_tokens': 0},
    };
  }

  /// Convert a single OpenAI SSE chunk to Anthropic SSE chunk format.
  Map<String, dynamic> _openAIChunkToAnthropic(
      Map<String, dynamic> openaiChunk) {
    final choices = openaiChunk['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return {'type': 'message_stop'};
    }

    final choice = choices[0] as Map<String, dynamic>;
    final delta = choice['delta'] as Map<String, dynamic>? ?? {};
    final finishReason = choice['finish_reason'] as String?;

    // If the chunk signals completion
    if (finishReason != null) {
      String anthropicStopReason;
      switch (finishReason) {
        case 'stop':
          anthropicStopReason = 'end_turn';
        case 'length':
          anthropicStopReason = 'max_tokens';
        default:
          anthropicStopReason = finishReason;
      }
      return {
        'type': 'message_delta',
        'delta': {
          'stop_reason': anthropicStopReason,
          'stop_sequence': choice['stop_sequence'],
        },
      };
    }

    // Content delta
    final content = delta['content'] as String?;
    if (content != null && content.isNotEmpty) {
      return {
        'type': 'content_block_delta',
        'index': choice['index'] ?? 0,
        'delta': {
          'type': 'text_delta',
          'text': content,
        },
      };
    }

    // Role announcement (first chunk)
    final role = delta['role'] as String?;
    if (role != null) {
      return {
        'type': 'message_start',
        'message': {
          'role': role,
          'content': [],
        },
      };
    }

    // Fallback – pass through as-is
    return openaiChunk;
  }

  // ------------------------------------------------------------------
  // Utilities
  // ------------------------------------------------------------------

  /// Parse the request body as JSON.
  Future<Map<String, dynamic>> _parseBody(shelf.Request request) async {
    final body = await request.readAsString();
    if (body.isEmpty) {
      throw FormatException('Empty body');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Body must be a JSON object');
    }
    return decoded;
  }

  /// Build a simple JSON error response.
  shelf.Response _errorResponse(int statusCode, String message) {
    _eventController.add(ProxyEvent(
      type: ProxyEventType.error,
      data: {'statusCode': statusCode, 'message': message},
    ));
    return shelf.Response(
      statusCode,
      body: jsonEncode({
        'error': {
          'message': message,
          'type': 'proxy_error',
          'code': statusCode,
        }
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Return all model names from all providers (for error messages).
  List<String> _allModelNames() {
    final names = <String>{};
    for (final p in _router.getAvailableProviders()) {
      names.addAll(p.models);
    }
    return names.toList()..sort();
  }
}
