import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/features/invoices/invoice_pdf_service.dart';
import 'package:vortice_app/features/invoices/invoice_excel_service.dart';
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

  // Editing controllers
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
    final consumables = hours * rate * 0.05;
    final formatted = consumables.toStringAsFixed(2);
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

    final labourTotal = (labourHours ?? 0) * (billableRate ?? 0);

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

  String _formatCurrency(double? value, {bool mxn = false}) {
    if (value == null) return mxn ? '\$0.00 MXN' : '\$0.00 USD';
    return mxn
        ? '\$${value.toStringAsFixed(2)} MXN'
        : '\$${value.toStringAsFixed(2)} USD';
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
            // Export PDF icon
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: l10n.exportPdf,
              onPressed: () async {
                final inv = invoiceAsync.valueOrNull;
                if (inv != null) await InvoicePdfService.generateAndShare(inv);
              },
            ),
            // Export Excel icon
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
          // Edit button — only available for draft invoices
          if (isOwner && !_isEditing)
            Builder(
              builder: (_) {
                final invoice = invoiceAsync.valueOrNull;
                final isLocked = invoice?.status == InvoiceStatus.sent ||
                    invoice?.status == InvoiceStatus.paid;
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
                // Header
                _InvoiceHeader(invoice: invoice),
                const SizedBox(height: 16),

                // Currency toggle
                _CurrencyToggle(
                  showMxn: _showMxn,
                  onChanged: (v) => setState(() => _showMxn = v),
                ),
                const SizedBox(height: 16),

                // Line items
                _isEditing
                    ? _EditableLineItems(
                        labourHoursCtrl: _labourHoursCtrl,
                        billableRateCtrl: _billableRateCtrl,
                        partsTotalCtrl: _partsTotalCtrl,
                        consumablesCtrl: _consumablesCtrl,
                        notesCtrl: _notesCtrl,
                      )
                    : _LineItemsCard(
                        invoice: invoice,
                        showMxn: _showMxn,
                        formatCurrency: _formatCurrency,
                      ),
                const SizedBox(height: 16),

                // Summary
                _SummaryCard(
                  invoice: invoice,
                  showMxn: _showMxn,
                  formatCurrency: _formatCurrency,
                ),
                const SizedBox(height: 24),

                // Actions
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
                        // 1. Generate PDF and open share/print sheet
                        await InvoicePdfService.generateAndShare(invoice);
                        // 2. Flip status to sent
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

class _InvoiceHeader extends StatelessWidget {
  final Invoice invoice;
  const _InvoiceHeader({required this.invoice});

  Color _statusColor() => switch (invoice.status) {
        InvoiceStatus.paid => AppColors.success,
        InvoiceStatus.sent => AppColors.warning,
        InvoiceStatus.draft => AppColors.textSecondary,
        InvoiceStatus.voided => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'INVOICE',
                style: TextStyle(
                  color: Color(0xFF93C5FD),
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  invoice.status.name.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            invoice.invoiceNumber,
            style: const TextStyle(
              color: Color(0xFF60A5FA),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _MetaItem(
                label: 'Created',
                value: invoice.createdAt != null
                    ? '${invoice.createdAt!.day}/${invoice.createdAt!.month}/${invoice.createdAt!.year}'
                    : '-',
              ),
              if (invoice.paidAt != null)
                _MetaItem(
                  label: 'Paid',
                  value:
                      '${invoice.paidAt!.day}/${invoice.paidAt!.month}/${invoice.paidAt!.year}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final String label;
  final String value;
  const _MetaItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: Color(0xFF93C5FD)),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CurrencyToggle extends StatelessWidget {
  final bool showMxn;
  final ValueChanged<bool> onChanged;

  const _CurrencyToggle({required this.showMxn, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CurrencyButton(
          label: 'USD',
          flag: '\u{1F1FA}\u{1F1F8}',
          selected: !showMxn,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        _CurrencyButton(
          label: 'MXN',
          flag: '\u{1F1F2}\u{1F1FD}',
          selected: showMxn,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _CurrencyButton extends StatelessWidget {
  final String label;
  final String flag;
  final bool selected;
  final VoidCallback onTap;

  const _CurrencyButton({
    required this.label,
    required this.flag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          '$flag $label',
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _LineItemsCard extends StatelessWidget {
  final Invoice invoice;
  final bool showMxn;
  final String Function(double?, {bool mxn}) formatCurrency;

  const _LineItemsCard({
    required this.invoice,
    required this.showMxn,
    required this.formatCurrency,
  });

  double _convert(double? usd) {
    if (usd == null) return 0;
    return showMxn ? usd * (invoice.exchangeRate ?? 1) : usd;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labourTotal =
        (invoice.labourHours ?? 0) * (invoice.billableRateUsd ?? 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lineItems.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Divider(height: 20),
          _LineItemRow(
            label: l10n.labour,
            detail:
                '${invoice.labourHours?.toStringAsFixed(1) ?? 0} hrs @ ${formatCurrency(invoice.billableRateUsd, mxn: showMxn)}/hr',
            amount: formatCurrency(_convert(labourTotal), mxn: showMxn),
          ),
          const SizedBox(height: 12),
          _LineItemRow(
            label: l10n.partsWithMarkup,
            amount:
                formatCurrency(_convert(invoice.partsTotalUsd), mxn: showMxn),
          ),
          const SizedBox(height: 12),
          _LineItemRow(
            label: l10n.consumables,
            detail: '5% of labour',
            amount: formatCurrency(_convert(invoice.consumablesTotalUsd),
                mxn: showMxn),
            isSubtle: true,
          ),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  final String label;
  final String? detail;
  final String amount;
  final bool isSubtle;

  const _LineItemRow({
    required this.label,
    this.detail,
    required this.amount,
    this.isSubtle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSubtle
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
            ],
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            color: isSubtle ? AppColors.textSecondary : const Color(0xFF60A5FA),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EditableLineItems extends StatelessWidget {
  final TextEditingController labourHoursCtrl;
  final TextEditingController billableRateCtrl;
  final TextEditingController partsTotalCtrl;
  final TextEditingController consumablesCtrl;
  final TextEditingController notesCtrl;

  const _EditableLineItems({
    required this.labourHoursCtrl,
    required this.billableRateCtrl,
    required this.partsTotalCtrl,
    required this.consumablesCtrl,
    required this.notesCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.editLineItems.toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: labourHoursCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.labourHours),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: billableRateCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.billableRate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: partsTotalCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.partsTotal),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: consumablesCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.consumables),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: notesCtrl,
            maxLines: 2,
            decoration: InputDecoration(labelText: l10n.notes),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Invoice invoice;
  final bool showMxn;
  final String Function(double?, {bool mxn}) formatCurrency;

  const _SummaryCard({
    required this.invoice,
    required this.showMxn,
    required this.formatCurrency,
  });

  double _convert(double? usd) {
    if (usd == null) return 0;
    return showMxn ? usd * (invoice.exchangeRate ?? 1) : usd;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1722),
        borderRadius: BorderRadius.circular(14),
        border: const Border.fromBorderSide(
            BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: l10n.subtotal,
            value: formatCurrency(_convert(invoice.subtotalUsd), mxn: showMxn),
          ),
          _SummaryRow(
            label: 'IVA (${invoice.ivaPct.toStringAsFixed(0)}%)',
            value: formatCurrency(_convert(invoice.ivaTotalUsd), mxn: showMxn),
          ),
          const Divider(color: AppColors.divider, height: 24),
          _SummaryRow(
            label: l10n.totalDue,
            value: showMxn
                ? formatCurrency(invoice.totalMxn, mxn: true)
                : formatCurrency(invoice.totalUsd, mxn: false),
            isGrand: true,
          ),
          if (!showMxn && invoice.totalMxn != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '(${formatCurrency(invoice.totalMxn, mxn: true)})',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          if (invoice.exchangeRate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${l10n.exchangeRate}: 1 USD = ${invoice.exchangeRate!.toStringAsFixed(4)} MXN',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isGrand;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isGrand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color:
                  isGrand ? const Color(0xFF60A5FA) : AppColors.textSecondary,
              fontSize: isGrand ? 18 : 14,
              fontWeight: isGrand ? FontWeight.w900 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isGrand ? const Color(0xFF60A5FA) : AppColors.textPrimary,
              fontSize: isGrand ? 20 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
