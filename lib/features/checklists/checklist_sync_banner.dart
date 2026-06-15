import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/sync/sync_status.dart';

class ChecklistSyncStatusBanner extends StatelessWidget {
  final bool hasConflict;
  final String message;
  final VoidCallback? onRetry;
  final bool isRetrying;

  const ChecklistSyncStatusBanner({
    super.key,
    required this.hasConflict,
    required this.message,
    this.onRetry,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasConflict ? AppColors.error : AppColors.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            hasConflict ? Icons.sync_problem : Icons.cloud_off,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: isRetrying ? null : onRetry,
              icon: isRetrying
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(Icons.sync, size: 16, color: color),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: color,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChecklistItemSyncChip extends StatelessWidget {
  final String syncStatus;

  const ChecklistItemSyncChip({super.key, required this.syncStatus});

  @override
  Widget build(BuildContext context) {
    final label = syncStatusChipLabel(syncStatus);
    if (label == null) return const SizedBox.shrink();

    final isError = syncStatus == SyncStatusValues.failed ||
        syncStatus == SyncStatusValues.conflict;
    final color = isError ? AppColors.error : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
