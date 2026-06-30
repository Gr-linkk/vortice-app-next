import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_parts_line_items_support.dart';
import 'package:vortice_app/features/parts/parts_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class WorkOrderPartsSection extends ConsumerWidget {
  final String workOrderId;
  final bool isOwnerOrEmployee;

  const WorkOrderPartsSection({
    super.key,
    required this.workOrderId,
    required this.isOwnerOrEmployee,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOwnerOrEmployee) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final partsAsync = ref.watch(partsProvider(workOrderId));

    return partsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (parts) {
        if (parts.isEmpty) return const SizedBox.shrink();

        final lines = buildInvoicePartLineItems(parts);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.partsWithMarkup.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatInvoicePartLineLabel(line),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            formatInvoicePartLineDetail(line),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '\$${line.lineTotalUsd.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              'Total: \$${sumInvoicePartLineTotals(lines).toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}
