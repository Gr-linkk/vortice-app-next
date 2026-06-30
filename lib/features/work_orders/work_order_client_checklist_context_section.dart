import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/saved_checklists_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_detail_support.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/saved_checklist.dart';
import 'package:vortice_app/models/work_order.dart';

class WorkOrderClientChecklistContextSection extends ConsumerWidget {
  final WorkOrder workOrder;

  const WorkOrderClientChecklistContextSection(
      {super.key, required this.workOrder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(
      savedChecklistsForAssetProvider(
        (assetId: workOrder.assetId, type: SavedChecklistType.maintenance),
      ),
    );

    return rowsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (rows) {
        final clientRows = rows
            .where((row) => row.sourceType == 'client')
            .take(3)
            .toList(growable: false);
        if (clientRows.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_toggle_off,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recent client checklists',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Reference only — these do not complete the work order checklist.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ...clientRows.map(
                (row) => WorkOrderClientChecklistReferenceTile(
                  workOrder: workOrder,
                  row: row,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class WorkOrderClientChecklistReferenceTile extends ConsumerWidget {
  final WorkOrder workOrder;
  final SavedChecklist row;

  const WorkOrderClientChecklistReferenceTile({
    super.key,
    required this.workOrder,
    required this.row,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagged = savedChecklistFlaggedCount(row);
    final dateLabel = DateFormat.MMMd().add_jm().format(row.submittedAt);
    final attached = (workOrder.notesInternal ?? '').contains(row.id);

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: AppColors.surfaceVariant.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.templateName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          dateLabel,
                          if (row.currentHours != null)
                            '${row.currentHours!.toStringAsFixed(0)}h',
                        ].join(' • '),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (flagged > 0)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                    label: Text(
                      '$flagged flagged',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      showWorkOrderSavedChecklistReference(context, row),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: attached
                      ? null
                      : () => _attachReference(context, ref, row),
                  icon: Icon(
                    attached ? Icons.check : Icons.attach_file,
                    size: 18,
                  ),
                  label: Text(attached ? 'Attached' : 'Attach reference'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attachReference(
    BuildContext context,
    WidgetRef ref,
    SavedChecklist row,
  ) async {
    final existing = workOrder.notesInternal?.trim();
    final dateLabel = DateFormat.yMMMd().add_jm().format(row.submittedAt);
    final reference = [
      'Client checklist reference:',
      row.templateName,
      dateLabel,
      if (row.currentHours != null) '${row.currentHours!.toStringAsFixed(0)}h',
      'id:${row.id}',
    ].join(' • ');
    final nextNotes = existing == null || existing.isEmpty
        ? reference
        : '$existing\n\n$reference';

    final success =
        await ref.read(workOrderControllerProvider.notifier).updateWorkOrder(
      workOrder.id,
      {'notes_internal': nextNotes},
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Client checklist attached as WO reference.'
              : 'Could not attach reference right now.',
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }
}

void showWorkOrderSavedChecklistReference(
    BuildContext context, SavedChecklist row) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => WorkOrderSavedChecklistReferenceSheet(row: row),
  );
}

class WorkOrderSavedChecklistReferenceSheet extends StatelessWidget {
  final SavedChecklist row;

  const WorkOrderSavedChecklistReferenceSheet({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final header = row.snapshot['header'] as Map<String, dynamic>? ?? const {};
    final items = (row.snapshot['items'] as List?)?.cast<Map>() ?? const [];
    final submittedLabel = DateFormat.yMMMd().add_jm().format(row.submittedAt);

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(row.templateName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Client-submitted checklist reference',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            WorkOrderSavedChecklistHeaderLine(
                label: 'Submitted', value: submittedLabel),
            WorkOrderSavedChecklistHeaderLine(
              label: 'Completed by',
              value: '${header['completed_by'] ?? row.submittedBy ?? '—'}',
            ),
            if (row.currentHours != null)
              WorkOrderSavedChecklistHeaderLine(
                label: 'Hours',
                value: row.currentHours!.toStringAsFixed(0),
              ),
            if ((row.generalNotes ?? '').trim().isNotEmpty)
              WorkOrderSavedChecklistHeaderLine(
                  label: 'Notes', value: row.generalNotes!.trim()),
            const SizedBox(height: 12),
            ...items.map((item) {
              final response = (item['response'] ?? '').toString();
              final note = (item['note'] ?? '').toString();
              final isFlagged = response == 'monitor' || response == 'action';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  (item['description_en'] ?? 'Checklist item').toString(),
                ),
                subtitle: note.isNotEmpty ? Text(note) : null,
                trailing: Text(
                  response.toUpperCase(),
                  style: TextStyle(
                    color: isFlagged ? AppColors.warning : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class WorkOrderSavedChecklistHeaderLine extends StatelessWidget {
  final String label;
  final String value;

  const WorkOrderSavedChecklistHeaderLine(
      {super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
