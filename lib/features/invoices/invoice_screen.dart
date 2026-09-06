import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';

class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key});

  Future<void> _showGenerateDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final isOwner =
        ref.read(profileProvider).valueOrNull?.role == UserRole.owner;
    if (!isOwner) return;

    // Fetch review-ready WOs that can be invoiced.
    final woData = await supabase
        .from(AppConstants.tWorkOrders)
        .select('id, title, status')
        .inFilter('status', [
      WorkOrderStatus.pendingReview.dbValue,
      WorkOrderStatus.closed.dbValue,
    ]);

    if (!context.mounted) return;

    String? selectedWoId;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.selectWorkOrderForInvoice,
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 16),
              if ((woData as List).isEmpty)
                Text(l10n.noCompletedWorkOrders,
                    style: const TextStyle(color: AppColors.textSecondary))
              else
                DropdownButtonFormField<String>(
                  initialValue: selectedWoId,
                  decoration: const InputDecoration(),
                  dropdownColor: AppColors.surfaceVariant,
                  items: (woData as List)
                      .map((w) => DropdownMenuItem<String>(
                            value: w['id'] as String,
                            child: Text(w['title'] as String,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setSheetState(() => selectedWoId = v),
                ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: selectedWoId == null
                    ? null
                    : () async {
                        Navigator.of(ctx).pop();
                        final newId = await ref
                            .read(invoiceControllerProvider.notifier)
                            .generateFromWorkOrder(selectedWoId!);
                        if (!context.mounted) return;
                        if (newId != null) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(l10n.invoiceGenerated),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          final basePath =
                              ref.read(profileProvider).valueOrNull?.role ==
                                      UserRole.owner
                                  ? '/owner'
                                  : '/client';
                          context.push('$basePath/invoices/$newId');
                        } else {
                          final error =
                              ref.read(invoiceControllerProvider).error;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  error == null
                                      ? 'Invoice generation failed.'
                                      : 'Invoice generation failed: $error',
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                        }
                      },
                icon: const Icon(Icons.receipt_long),
                label: Text(l10n.generateInvoice),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final invoicesAsync = ref.watch(invoicesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final isOwner = profile?.role == UserRole.owner;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.invoicesTitle)),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () => _showGenerateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.generateInvoice),
            )
          : null,
      body: invoicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(friendlyError(context, err),
                  style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(invoicesProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (invoices) {
          if (invoices.isEmpty) {
            return Center(
              child: Text(l10n.noInvoices,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }

          // Group by status
          final unpaid = invoices
              .where((i) =>
                  i.status == InvoiceStatus.sent ||
                  i.status == InvoiceStatus.draft)
              .toList();
          final paid =
              invoices.where((i) => i.status == InvoiceStatus.paid).toList();
          final voided =
              invoices.where((i) => i.status == InvoiceStatus.voided).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(invoicesProvider),
            child: ListView(
              children: [
                if (unpaid.isNotEmpty) ...[
                  _SectionHeader(label: l10n.unpaid, color: AppColors.warning),
                  ...unpaid.map((i) => _InvoiceTile(invoice: i)),
                ],
                if (paid.isNotEmpty) ...[
                  _SectionHeader(label: l10n.paid, color: AppColors.success),
                  ...paid.map((i) => _InvoiceTile(invoice: i)),
                ],
                if (voided.isNotEmpty) ...[
                  const _SectionHeader(
                      label: 'VOIDED', color: AppColors.textSecondary),
                  ...voided.map((i) => _InvoiceTile(invoice: i)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  final Invoice invoice;
  const _InvoiceTile({required this.invoice});

  Color _statusColor() => switch (invoice.status) {
        InvoiceStatus.paid => AppColors.success,
        InvoiceStatus.sent => AppColors.warning,
        InvoiceStatus.draft => AppColors.textSecondary,
        InvoiceStatus.voided => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final total = invoice.totalUsd ?? 0;
    final profile = ref.watch(profileProvider).valueOrNull;
    final basePath = profile?.role == UserRole.owner ? '/owner' : '/client';
    final canMarkPaid = canMarkInvoicePaidFromList(
      role: profile?.role,
      status: invoice.status,
    );
    final statusLabel = switch (invoice.status) {
      InvoiceStatus.paid => l10n.paid,
      InvoiceStatus.sent => 'SENT',
      InvoiceStatus.draft => 'DRAFT',
      InvoiceStatus.voided => 'VOID',
    };

    return Card(
      child: ListTile(
        onTap: () => context.push('$basePath/invoices/${invoice.id}'),
        leading: CircleAvatar(
          backgroundColor: _statusColor().withValues(alpha: 0.15),
          child: Icon(
            invoice.status == InvoiceStatus.paid
                ? Icons.check_circle
                : invoice.status == InvoiceStatus.voided
                    ? Icons.cancel
                    : Icons.receipt_long,
            color: _statusColor(),
            size: 20,
          ),
        ),
        title: Text(
          invoice.invoiceNumber,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '\$${total.toStringAsFixed(2)} USD',
              style: TextStyle(
                color: _statusColor(),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (invoice.totalMxn != null)
              Text(
                '\$${invoice.totalMxn!.toStringAsFixed(2)} MXN',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
          ],
        ),
        trailing: canMarkPaid
            ? TextButton(
                onPressed: () async {
                  final success = await ref
                      .read(invoiceControllerProvider.notifier)
                      .markAsPaid(invoice.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? l10n.invoiceMarkedPaid
                            : 'Could not mark invoice paid.'),
                        backgroundColor:
                            success ? AppColors.success : AppColors.error,
                      ),
                    );
                },
                child: Text(l10n.markPaid),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      color: _statusColor(),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
        isThreeLine: true,
      ),
    );
  }
}
