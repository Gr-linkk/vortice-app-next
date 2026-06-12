import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';

class OrgAdminInvoicesTab extends ConsumerWidget {
  const OrgAdminInvoicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);

    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          err.toString(),
          style: const TextStyle(color: AppColors.error),
        ),
      ),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('No invoices yet.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final inv = invoices[i];
            final color = orgAdminInvoiceStatusColor(inv.status);
            return InkWell(
              onTap: () => context.push('/client/invoices/${inv.id}'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inv.invoiceNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          if (inv.totalUsd != null)
                            Text(
                              '\$${inv.totalUsd!.toStringAsFixed(2)} USD',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        inv.status.name.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
