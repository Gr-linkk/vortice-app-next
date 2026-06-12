import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/pm_part_requirement_sheet.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';

class PmPartsListSheet extends ConsumerWidget {
  final String templateId;
  final String templateName;
  final bool canEdit;

  const PmPartsListSheet({
    super.key,
    required this.templateId,
    required this.templateName,
    this.canEdit = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(pmPartsRequirementsProvider(templateId));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      templateName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (canEdit)
                    TextButton.icon(
                      onPressed: () => _showPartSheet(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: partsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    const Center(child: Text('Could not load parts list.')),
                data: (parts) {
                  if (parts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No parts list for this service.',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                            if (canEdit) ...[
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => _showPartSheet(context),
                                icon: const Icon(Icons.add),
                                label: const Text('Add first part'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: ctrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: parts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final part = parts[i];
                      return InkWell(
                        onTap: canEdit
                            ? () => _showPartSheet(context, requirement: part)
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(part.description,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    if (part.partNumber != null)
                                      Text('PN: ${part.partNumber}',
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12)),
                                    if (part.notes != null)
                                      Text(part.notes!,
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              Text(
                                '${part.qty} ${part.unit ?? 'ea'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              if (canEdit) ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Delete part',
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.error, size: 20),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: AppColors.surface,
                                        title: const Text('Delete part?'),
                                        content: Text(part.description),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Delete',
                                                style: TextStyle(
                                                    color: AppColors.error)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      await ref
                                          .read(pmPartsControllerProvider
                                              .notifier)
                                          .removeRequirement(
                                              part.id, templateId);
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPartSheet(BuildContext context, {PmPartsRequirement? requirement}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PmPartRequirementSheet(
        templateId: templateId,
        requirement: requirement,
      ),
    );
  }
}
