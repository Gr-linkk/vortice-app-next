import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/pm_kits_screen.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';

class WorkOrderPmKitSection extends ConsumerWidget {
  final String templateId;
  const WorkOrderPmKitSection({super.key, required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(pmPartsRequirementsProvider(templateId));

    return partsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (parts) {
        if (parts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: context.appColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PM PARTS KIT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.appColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => PmPartsListSheet(
                        templateId: templateId,
                        templateName: 'Parts Required',
                      ),
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
            ),
            ...parts
                .take(5)
                .map(
                  (part) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 5,
                          color: context.appColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            part.description,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (part.partNumber != null)
                          Text(
                            part.partNumber!,
                            style: TextStyle(
                              color: context.appColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          '${part.qty} ${part.unit ?? 'ea'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (parts.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  '+${parts.length - 5} more — tap View all',
                  style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
