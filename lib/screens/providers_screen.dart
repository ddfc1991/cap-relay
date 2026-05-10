import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/provider_config.dart';
import '../services/app_state.dart';

/// Provider management screen with active/inactive toggles, API key editing,
/// swipe-to-delete, and pull-to-refresh.
class ProvidersScreen extends StatelessWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.resetAllExhausted();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Exhausted providers reset'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: appState.providers.isEmpty
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 64, color: colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No providers configured',
                            style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + to add a custom provider',
                            style: TextStyle(
                                color:
                                    colorScheme.onSurfaceVariant.withOpacity(0.7),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, top: 8, bottom: 80),
                itemCount: appState.providers.length,
                itemBuilder: (context, index) {
                  final provider = appState.providers[index];
                  return _ProviderListItem(
                    provider: provider,
                    status: appState.effectiveStatus(provider.id),
                    onToggle: () =>
                        appState.toggleProvider(provider.id),
                    onEditApiKey: () =>
                        _showEditApiKeyDialog(context, appState, provider),
                    onDelete: () =>
                        _confirmDelete(context, appState, provider),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProviderDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Provider'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
    );
  }

  // ── Edit API Key Dialog ─────────────────────────────────────────────

  void _showEditApiKeyDialog(
      BuildContext context, AppState appState, ProviderConfig provider) {
    final controller = TextEditingController(text: provider.apiKey ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('API Key — ${provider.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'API Key',
            border: OutlineInputBorder(),
            hintText: 'sk-...',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.updateApiKey(provider.id, controller.text.trim());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('API key updated'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Delete Confirmation Dialog ──────────────────────────────────────

  void _confirmDelete(
      BuildContext context, AppState appState, ProviderConfig provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Provider'),
        content: Text('Remove "${provider.name}" from providers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              appState.deleteProvider(provider.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${provider.name} deleted'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Add Provider Dialog ─────────────────────────────────────────────

  void _showAddProviderDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final baseUrlCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Custom Provider'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. My Provider',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: baseUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                  hintText: 'https://api.example.com/v1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Models (comma-separated)',
                  border: OutlineInputBorder(),
                  hintText: 'model-1, model-2',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyCtrl,
                decoration: const InputDecoration(
                  labelText: 'API Key (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'sk-...',
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final baseUrl = baseUrlCtrl.text.trim();
              if (name.isEmpty || baseUrl.isEmpty) return;

              final models = modelCtrl.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

              final id = name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');

              final provider = ProviderConfig(
                id: id,
                name: name,
                baseUrl: baseUrl,
                models: models,
                priority: 0,
              );

              if (apiKeyCtrl.text.trim().isNotEmpty) {
                provider.apiKey = apiKeyCtrl.text.trim();
              }

              context.read<AppState>().addProvider(provider);

              // Save the API key separately if provided
              if (apiKeyCtrl.text.trim().isNotEmpty) {
                context
                    .read<AppState>()
                    .updateApiKey(id, apiKeyCtrl.text.trim());
              }

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Provider "$name" added'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ── Provider List Item ─────────────────────────────────────────────────

class _ProviderListItem extends StatelessWidget {
  final ProviderConfig provider;
  final ProviderStatus status;
  final VoidCallback onToggle;
  final VoidCallback onEditApiKey;
  final VoidCallback onDelete;

  const _ProviderListItem({
    required this.provider,
    required this.status,
    required this.onToggle,
    required this.onEditApiKey,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color statusColor;
    String statusLabel;
    switch (status) {
      case ProviderStatus.active:
        statusColor = Colors.greenAccent;
        statusLabel = 'Active';
      case ProviderStatus.quotaExhausted:
        statusColor = Colors.orangeAccent;
        statusLabel = 'Exhausted';
      case ProviderStatus.error:
        statusColor = Colors.redAccent;
        statusLabel = 'Error';
    }

    return Dismissible(
      key: Key(provider.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_rounded,
            color: colorScheme.onError, size: 28),
      ),
      confirmDismiss: (_) async {
        // Use the confirmation dialog instead
        onDelete();
        return false;
      },
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: colorScheme.surfaceContainerHighest,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEditApiKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    boxShadow: [
                      BoxShadow(
                          color: statusColor.withOpacity(0.4),
                          blurRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Provider info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider.baseUrl,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _infoChip(
                            Icons.bar_chart_rounded,
                            '${provider.usageCount}',
                            colorScheme,
                          ),
                          const SizedBox(width: 8),
                          _infoChip(
                            Icons.label_rounded,
                            statusLabel,
                            colorScheme,
                            labelColor: statusColor,
                          ),
                          if (provider.apiKey != null &&
                              provider.apiKey!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _infoChip(
                              Icons.vpn_key_rounded,
                              'Key set',
                              colorScheme,
                              labelColor: Colors.blueAccent,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Active toggle
                Switch(
                  value: provider.isActive,
                  onChanged: (_) => onToggle(),
                  activeColor: colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(
    IconData icon,
    String label,
    ColorScheme colorScheme, {
    Color? labelColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (labelColor ?? colorScheme.onSurfaceVariant)
            .withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: labelColor ?? colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: labelColor ?? colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
