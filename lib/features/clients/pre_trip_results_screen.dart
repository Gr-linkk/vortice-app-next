import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';

/// Screen for clients to view pre-trip check results for an asset
class PreTripResultsScreen extends ConsumerWidget {
  final String assetId;
  final String assetName;

  const PreTripResultsScreen({
    super.key,
    required this.assetId,
    required this.assetName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final runsAsync = ref.watch(operatorRunsForAssetProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.preTripResults),
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

          // Checklist runs list
          Expanded(
            child: runsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(err.toString(),
                    style: const TextStyle(color: AppColors.error)),
              ),
              data: (runs) {
                if (runs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checklist,
                            size: 48, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noPreTripChecks,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(operatorRunsForAssetProvider(assetId)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: runs.length,
                    itemBuilder: (_, i) => _ChecklistRunCard(run: runs[i]),
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

class _ChecklistRunCard extends ConsumerWidget {
  final OperatorChecklistRun run;
  const _ChecklistRunCard({required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hasFlagged = run.hasFlaggedItems;
    final flaggedCount = run.flaggedCount;
    final totalCount = run.responses.length;
    final passedCount = run.responses.where((r) => r.result == 'good').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: hasFlagged
              ? AppColors.warning.withOpacity(0.15)
              : AppColors.success.withOpacity(0.15),
          child: Icon(
            hasFlagged ? Icons.warning_amber_rounded : Icons.check_circle,
            color: hasFlagged ? AppColors.warning : AppColors.success,
            size: 20,
          ),
        ),
        title: Text(
          _formatDate(run.completedAt ?? run.createdAt),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.preDeparture,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _StatBadge(
                  icon: Icons.check,
                  label: '$passedCount',
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                if (flaggedCount > 0)
                  _StatBadge(
                    icon: Icons.warning_amber,
                    label: '$flaggedCount',
                    color: AppColors.warning,
                  ),
              ],
            ),
          ],
        ),
        children: [
          const Divider(height: 1),
          ...run.responses.map((response) => _ResponseTile(response: response)),
          if (run.notes != null && run.notes!.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      run.notes!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ResponseTile extends ConsumerWidget {
  final OperatorChecklistResponse response;
  const _ResponseTile({required this.response});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Try to get the checklist item description
    final itemsAsync = ref.watch(allChecklistItemsProvider);
    final itemDescription = itemsAsync.whenOrNull(
      data: (items) {
        final item = items.where((i) => i.id == response.checklistItemId).firstOrNull;
        return item?.descriptionEn;
      },
    ) as String?;

    final color = switch (response.result) {
      'good' => AppColors.success,
      'needs_attention' => AppColors.warning,
      _ => AppColors.textSecondary,
    };

    final icon = switch (response.result) {
      'good' => Icons.check_circle,
      'needs_attention' => Icons.warning_amber_rounded,
      _ => Icons.remove_circle_outline,
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        itemDescription ?? 'Checklist item',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: response.notes != null && response.notes!.isNotEmpty
          ? Text(
              response.notes!,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            )
          : null,
    );
  }
}

/// Provider to fetch all checklist items (for looking up descriptions)
final allChecklistItemsProvider = FutureProvider((ref) async {
  final data = await ref.watch(checklistTemplatesProvider.future);
  final allItems = <dynamic>[];
  for (final template in data) {
    final items = await ref.watch(checklistItemsProvider(template.id).future);
    allItems.addAll(items);
  }
  return allItems;
});
