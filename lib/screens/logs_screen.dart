import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/provider_config.dart';
import '../services/app_state.dart';

/// Request logs screen showing a scrollable list of recent requests.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    if (!_autoScroll || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;
    final logs = appState.requestLogs;

    // Auto-scroll when new logs arrive
    if (logs.isNotEmpty) {
      _scrollToLatest();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Logs'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          if (logs.isNotEmpty)
            IconButton(
              onPressed: () {
                appState.clearLogs();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logs cleared'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: Icon(Icons.delete_sweep_rounded,
                  color: colorScheme.onSurfaceVariant),
              tooltip: 'Clear logs',
            ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded,
                      size: 64, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'No request logs yet',
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Requests will appear here as they are processed',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Auto-scroll toggle
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_downward_rounded,
                          size: 16, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Auto-scroll',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _autoScroll,
                        onChanged: (v) => setState(() => _autoScroll = v),
                        activeColor: colorScheme.primary,
                        // dense parameter not supported in Flutter 3.27
                      ),
                      const Spacer(),
                      Text(
                        '${logs.length} entries',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Log list
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return _LogListItem(
                        log: log,
                        colorScheme: colorScheme,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Log List Item ──────────────────────────────────────────────────────

class _LogListItem extends StatelessWidget {
  final RequestLog log;
  final ColorScheme colorScheme;

  const _LogListItem({
    required this.log,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final timestampStr = _formatTimestamp(log.timestamp);
    final durationStr =
        log.duration != null ? _formatDuration(log.duration!) : 'pending';
    final isPending = log.statusCode == null;

    final Color statusColor;
    if (isPending) {
      statusColor = Colors.grey;
    } else if (log.statusCode! >= 200 && log.statusCode! < 300) {
      statusColor = Colors.greenAccent;
    } else if (log.statusCode! >= 400 && log.statusCode! < 500) {
      statusColor = Colors.orangeAccent;
    } else {
      statusColor = Colors.redAccent;
    }

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: timestamp + status
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  timestampStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPending ? '...' : '${log.statusCode}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    durationStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Model
            Row(
              children: [
                Icon(Icons.smart_toy_rounded,
                    size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    log.model,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Provider
            Row(
              children: [
                Icon(Icons.cloud_rounded,
                    size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  log.provider,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String _formatDuration(Duration d) {
    if (d.inMilliseconds < 1000) {
      return '${d.inMilliseconds}ms';
    }
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
}
