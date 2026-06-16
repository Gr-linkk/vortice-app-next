import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';

/// Screen for clients to view maintenance flags for an asset
class MaintenanceFlagsScreen extends ConsumerWidget {
  final String assetId;
  final String assetName;

  const MaintenanceFlagsScreen({
    super.key,
    required this.assetId,
    required this.assetName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final flagsAsync = ref.watch(maintenanceRequestsForAssetProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.maintenanceFlags),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Asset header
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surfaceVariant,
            child: Row(
              children: [
                const Icon(Icons.directions_boat, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    assetName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),

          // Flags list
          Expanded(
            child: flagsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(err.toString(),
                    style: const TextStyle(color: AppColors.error)),
              ),
              data: (flags) {
                if (flags.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flag_outlined,
                            size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noMaintenanceFlags,
                          style:
                              const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                // Group by status
                final open = flags.where((f) => f.isOpen).toList();
                final resolved = flags.where((f) => !f.isOpen).toList();

                return RefreshIndicator(
                  onRefresh: () async => ref
                      .invalidate(maintenanceRequestsForAssetProvider(assetId)),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (open.isNotEmpty) ...[
                        _SectionHeader(
                          label: l10n.openIssues,
                          count: open.length,
                          color: AppColors.warning,
                        ),
                        ...open.map((f) => _FlagCard(flag: f)),
                        const SizedBox(height: 16),
                      ],
                      if (resolved.isNotEmpty) ...[
                        _SectionHeader(
                          label: l10n.resolvedIssues,
                          count: resolved.length,
                          color: AppColors.textSecondary,
                        ),
                        ...resolved.map((f) => _FlagCard(flag: f)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagCard extends StatelessWidget {
  final MaintenanceRequest flag;
  const _FlagCard({required this.flag});

  @override
  Widget build(BuildContext context) {
    final isUrgent = flag.isUrgent;
    final statusColor = flag.isOpen
        ? (isUrgent ? AppColors.error : AppColors.warning)
        : AppColors.success;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  flag.isOpen ? Icons.flag : Icons.check_circle,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                if (isUrgent && flag.isOpen)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'URGENT',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  _formatDate(flag.createdAt),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              flag.description,
              style: const TextStyle(fontSize: 14),
            ),
            if (!flag.isOpen) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      _statusLabel(flag.status),
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _statusLabel(String status) => switch (status) {
        'acknowledged' => 'Acknowledged',
        'converted' => 'In Service Review',
        'dismissed' => 'Dismissed',
        _ => status,
      };
}
