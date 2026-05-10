import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/provider_config.dart';
import '../services/app_state.dart';

/// Main dashboard screen showing server status, active provider,
/// request counter, and provider health indicators.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CAP 中转'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Server Status Card ─────────────────────────────────────
          _ServerStatusCard(
            serverRunning: appState.serverRunning,
            port: appState.config.serverPort,
            onStart: () => _handleStart(context),
            onStop: () => _handleStop(context),
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 16),

          // ── Active Provider Card ───────────────────────────────────
          _ActiveProviderCard(
            provider: appState.currentProvider,
            status: appState.currentProvider != null
                ? appState.effectiveStatus(appState.currentProvider!.id)
                : ProviderStatus.error,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 16),

          // ── Request Counter Card ───────────────────────────────────
          _RequestCounterCard(
            count: appState.requestCount,
            logCount: appState.requestLogs.length,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 16),

          // ── Provider Health Card ───────────────────────────────────
          _ProviderHealthCard(
            providers: appState.providers,
            getStatus: (id) => appState.effectiveStatus(id),
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Future<void> _handleStart(BuildContext context) async {
    try {
      await context.read<AppState>().startServer();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('服务器已启动'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _handleStop(BuildContext context) async {
    await context.read<AppState>().stopServer();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('服务器已停止'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Server Status Card ─────────────────────────────────────────────────

class _ServerStatusCard extends StatelessWidget {
  final bool serverRunning;
  final int port;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ColorScheme colorScheme;

  const _ServerStatusCard({
    required this.serverRunning,
    required this.port,
    required this.onStart,
    required this.onStop,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  '服务器状态',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: serverRunning
                        ? colorScheme.primary.withOpacity(0.15)
                        : colorScheme.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              serverRunning ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        serverRunning ? '运行中' : '已停止',
                        style: TextStyle(
                          color: serverRunning
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.router_rounded,
                    size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '端口: $port',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: serverRunning ? onStop : onStart,
                icon: Icon(serverRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(serverRunning ? '停止服务器' : '启动服务器'),
                style: FilledButton.styleFrom(
                  backgroundColor: serverRunning
                      ? colorScheme.error
                      : colorScheme.primary,
                  foregroundColor: serverRunning
                      ? colorScheme.onError
                      : colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Active Provider Card ───────────────────────────────────────────────

class _ActiveProviderCard extends StatelessWidget {
  final ProviderConfig? provider;
  final ProviderStatus status;
  final ColorScheme colorScheme;

  const _ActiveProviderCard({
    required this.provider,
    required this.status,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_rounded,
                    color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  '当前供应商',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (provider != null) ...[
              Row(
                children: [
                  _statusDot(status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider!.name,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          provider!.baseUrl,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Model: ${provider!.models.isNotEmpty ? provider!.models.first : 'N/A'}',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ] else ...[
              Text(
                '未配置供应商',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusDot(ProviderStatus s) {
    Color color;
    switch (s) {
      case ProviderStatus.active:
        color = Colors.greenAccent;
      case ProviderStatus.quotaExhausted:
        color = Colors.orangeAccent;
      case ProviderStatus.error:
        color = Colors.redAccent;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.4), blurRadius: 4),
        ],
      ),
    );
  }
}

// ── Request Counter Card ───────────────────────────────────────────────

class _RequestCounterCard extends StatelessWidget {
  final int count;
  final int logCount;
  final ColorScheme colorScheme;

  const _RequestCounterCard({
    required this.count,
    required this.logCount,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.bar_chart_rounded,
                  color: colorScheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '请求数',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count total',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '已记录 $logCount 条',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              '$count',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Provider Health Card ───────────────────────────────────────────────

class _ProviderHealthCard extends StatelessWidget {
  final List<ProviderConfig> providers;
  final ProviderStatus Function(String id) getStatus;
  final ColorScheme colorScheme;

  const _ProviderHealthCard({
    required this.providers,
    required this.getStatus,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart_rounded,
                    color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  '供应商状态',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (providers.isEmpty)
              Text(
                '未配置供应商',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              ...providers.map((p) => _buildProviderRow(p)),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderRow(ProviderConfig provider) {
    final status = getStatus(provider.id);
    Color dotColor;
    String statusLabel;
    switch (status) {
      case ProviderStatus.active:
        dotColor = Colors.greenAccent;
        statusLabel = '活跃';
      case ProviderStatus.quotaExhausted:
        dotColor = Colors.orangeAccent;
        statusLabel = '已耗尽';
      case ProviderStatus.error:
        dotColor = Colors.redAccent;
        statusLabel = '错误';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(color: dotColor.withOpacity(0.4), blurRadius: 3),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: dotColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 11,
                color: dotColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
