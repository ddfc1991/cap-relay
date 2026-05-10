import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';

/// Settings screen with port configuration, auto-failover toggle,
/// API key management, and about section.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Server Port ─────────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.router_rounded,
                          color: colorScheme.primary, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        '服务器端口',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('port_input'),
                    controller: TextEditingController(
                      text: appState.config.serverPort.toString(),
                    ),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '端口号',
                      hintText: '8317',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.numbers_rounded),
                    ),
                    onSubmitted: (value) {
                      final port = int.tryParse(value.trim());
                      if (port != null && port > 0 && port <= 65535) {
                        appState.updatePort(port);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('端口已更新为 $port'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('端口号无效（1-65535）'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: colorScheme.error,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '默认8317，重启服务器后生效',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Auto-Failover ───────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.autorenew_rounded,
                      color: colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '自动切换',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '故障时自动切换到下一个可用供应商',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: appState.config.autoFailover,
                    onChanged: (_) => appState.toggleAutoFailover(),
                    activeColor: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── API Keys ────────────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.vpn_key_rounded,
                          color: colorScheme.primary, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        'API密钥管理',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () =>
                            _showAddApiKeyDialog(context, appState),
                        icon: Icon(Icons.add_circle_rounded,
                            color: colorScheme.primary),
                        tooltip: '添加API密钥',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (appState.config.apiKeys.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '未存储全局API密钥',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else
                    ...appState.config.apiKeys.map((key) {
                      final masked = key.length > 8
                          ? '${key.substring(0, 4)}...${key.substring(key.length - 4)}'
                          : '***';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.key_rounded,
                                size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                masked,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => appState.removeApiKey(key),
                              icon: Icon(Icons.remove_circle_outline_rounded,
                                  size: 20,
                                  color: colorScheme.error),
                              tooltip: '删除密钥',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Provider API Keys Summary ───────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_rounded,
                          color: colorScheme.primary, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        '供应商密钥',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在供应商页面为每个供应商单独设置API密钥',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...appState.providers.map((p) {
                    final hasKey =
                        p.apiKey != null && p.apiKey!.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            hasKey
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 16,
                            color: hasKey
                                ? Colors.greenAccent
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            p.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          const Spacer(),
                          Text(
                            hasKey ? '密钥已设置' : '无密钥',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── About ───────────────────────────────────────────────────
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: colorScheme.primary, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        '关于',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _aboutRow(
                    'CAP 中转',
                    'v1.0.0',
                    colorScheme,
                  ),
                  const SizedBox(height: 6),
                  _aboutRow(
                    '说明',
                    'A local API relay/middleware for AI providers with auto-failover',
                    colorScheme,
                  ),
                  const SizedBox(height: 6),
                  _aboutRow(
                    '已配置供应商',
                    '${appState.providers.length}',
                    colorScheme,
                  ),
                  const SizedBox(height: 6),
                  _aboutRow(
                    '服务器状态',
                    appState.serverRunning ? '运行中' : '已停止',
                    colorScheme,
                    valueColor: appState.serverRunning
                        ? Colors.greenAccent
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_rounded,
                            size: 18, color: colorScheme.tertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '在供应商页面配置供应商和API密钥，'
                            '然后在仪表盘启动服务器。',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _aboutRow(
    String label,
    String value,
    ColorScheme colorScheme, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  // ── Add API Key Dialog ──────────────────────────────────────────────

  void _showAddApiKeyDialog(BuildContext context, AppState appState) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('添加API密钥'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'API密钥',
            border: OutlineInputBorder(),
            hintText: 'sk-...',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final key = controller.text.trim();
              if (key.isNotEmpty) {
                appState.addApiKey(key);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('API密钥已添加'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
