import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/pm_parts_provider.dart';

class CreateWorkOrderPmPartsPreview extends ConsumerWidget {
  final String templateId;

  const CreateWorkOrderPmPartsPreview({
    super.key,
    required this.templateId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ref.watch(pmPartsRequirementsProvider(templateId)).when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (parts) {
              if (parts.isEmpty) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            color: AppColors.primary, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Parts required',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...parts.map(
                      (part) => Padding(
                        padding: const EdgeInsets.only(left: 26, bottom: 4),
                        child: Text(
                          '• ${part.description} — ${part.qty} ${part.unit ?? 'ea'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }
}
