import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/invoices/invoice_pdf_service.dart';
import 'package:vortice_app/features/invoices/invoice_excel_service.dart';
import 'package:vortice_app/features/invoices/invoice_detail_currency_toggle.dart';
import 'package:vortice_app/features/invoices/invoice_detail_header.dart';
import 'package:vortice_app/features/invoices/invoice_detail_line_items.dart';
import 'package:vortice_app/features/invoices/invoice_detail_summary.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/profile.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String invoiceId;

  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  bool _showMxn = false;
  bool _isEditing = false;

  final _labourHoursCtrl = TextEditingController();
  final _billableRateCtrl = TextEditingController();
  final _partsTotalCtrl = TextEditingController();
  final _consumablesCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _labourHoursCtrl.addListener(_updateConsumables);
    _billableRateCtrl.addListener(_updateConsumables);
  }

  void _updateConsumables() {
    final hours = double.tryParse(_labourHoursCtrl.text) ?? 0;
    final rate = double.tryParse(_billableRateCtrl.text) ?? 0;
    final formatted = formatConsumablesTotal(hours, rate);
    if (_consumablesCtrl.text != formatted) {
      _consumablesCtrl.text = formatted;
    }
  }

  @override
  void dispose() {
    _labourHoursCtrl.removeListener(_updateConsumables);
    _billableRateCtrl.removeListener(_updateConsumables);
    _labourHoursCtrl.dispose();
    _billableRateCtrl.dispose();
    _partsTotalCtrl.dispose();
    _consumablesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _initControllers(Invoice invoice) {
    _labourHoursCtrl.text = invoice.labourHours?.toStringAsFixed(2) ?? '0.00';
    _billableRateCtrl.text =
        invoice.billableRateUsd?.toStringAsFixed(2) ?? '60.00';
    _partsTotalCtrl.text = invoice.partsTotalUsd?.toStringAsFixed(2) ?? '0.00';
    _consumablesCtrl.text =
        invoice.consumablesTotalUsd?.toStringAsFixed(2) ?? '0.00';
    _notesCtrl.text = invoice.notes ?? '';
  }

  Future<void> _saveChanges() async {
    final labourHours = double.tryParse(_labourHoursCtrl.text);
    final billableRate = double.tryParse(_billableRateCtrl.text);
    final partsTotal = double.tryParse(_partsTotalCtrl.text);
    final consumables = double.tryParse(_consumablesCtrl.text);

    final labourTotal = computeLabourTotal(labourHours, billableRate);

    final success =
        await ref.read(invoiceControllerProvider.notifier).updateLineItems(
              widget.invoiceId,
              labourHours: labourHours,
              billableRate: billableRate,
              labourTotal: labourTotal,
              partsTotal: partsTotal,
              consumablesTotal: consumables,
              notes: _notesCtrl.text.trim().isNotEmpty
                  ? _notesCtrl.text.trim()
                  : null,
            );

    if (success && mounted) {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).invoiceSaved),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invoiceAsync = ref.watch(invoiceByIdProvider(widget.invoiceId));
    final profile = ref.watch(profileProvider).valueOrNull;
    final isOwner = profile?.role == UserRole.owner;
    final isLoading = ref.watch(invoiceControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.invoiceDetail),
        actions: [
          if (isOwner) ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: l10n.exportPdf,
              onPressed: () async {
                final inv = invoiceAsync.valueOrNull;
                if (inv != null) await InvoicePdfService.generateAndShare(inv);
              },
            ),
            IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: l10n.exportExcel,
              onPressed: () async {
                final inv = invoiceAsync.valueOrNull;
                if (inv != null) {
                  await InvoiceExcelService.generateAndShare(inv);
                }
              },
            ),
          ],
          if (isOwner && !_isEditing)
            Builder(
              builder: (_) {
                final invoice = invoiceAsync.valueOrNull;
                final isLocked =
                    invoice != null && isInvoiceEditingLocked(invoice.status);
                return IconButton(
                  icon: Icon(isLocked ? Icons.lock_outline : Icons.edit),
                  onPressed: isLocked
                      ? null
                      : () {
                          if (invoice != null) {
                            _initControllers(invoice);
                            setState(() => _isEditing = true);
                          }
                        },
                  tooltip: isLocked ? null : l10n.edit,
                );
              },
            ),
          if (isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'refresh_rate') {
                  await ref
                      .read(invoiceControllerProvider.notifier)
                      .refreshExchangeRate(widget.invoiceId);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'refresh_rate',
                  child: Row(
                    children: [
                      const Icon(Icons.currency_exchange, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.refreshExchangeRate),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: invoiceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (invoice) {
          if (invoice == null) {
            return Center(child: Text(l10n.notFound));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InvoiceDetailHeader(invoice: invoice),
                const SizedBox(height: 16),
                InvoiceDetailCurrencyToggle(
                  showMxn: _showMxn,
                  onChanged: (v) => setState(() => _showMxn = v),
                ),
                const SizedBox(height: 16),
                _isEditing
                    ? InvoiceDetailEditableLineItems(
                        labourHoursCtrl: _labourHoursCtrl,
                        billableRateCtrl: _billableRateCtrl,
                        partsTotalCtrl: _partsTotalCtrl,
                        consumablesCtrl: _consumablesCtrl,
                        notesCtrl: _notesCtrl,
                      )
                    : InvoiceDetailLineItemsCard(
                        invoice: invoice,
                        showMxn: _showMxn,
                      ),
                const SizedBox(height: 16),
                InvoiceDetailSummaryCard(
                  invoice: invoice,
                  showMxn: _showMxn,
                ),
                const SizedBox(height: 24),
                if (_isEditing) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _isEditing = false),
                          child: Text(l10n.cancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _saveChanges,
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(l10n.save),
                        ),
                      ),
                    ],
                  ),
                ] else if (isOwner) ...[
                  if (invoice.status == InvoiceStatus.draft) ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        await InvoicePdfService.generateAndShare(invoice);
                        await ref
                            .read(invoiceControllerProvider.notifier)
                            .updateStatus(widget.invoiceId, InvoiceStatus.sent);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.invoiceSent),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.send),
                      label: Text(l10n.sendInvoice),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (invoice.status != InvoiceStatus.paid &&
                      invoice.status != InvoiceStatus.voided)
                    ElevatedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(invoiceControllerProvider.notifier)
                            .markAsPaid(widget.invoiceId);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.invoiceMarkedPaid),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.check_circle),
                      label: Text(l10n.markPaid),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
