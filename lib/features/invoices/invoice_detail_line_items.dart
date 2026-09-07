import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/features/invoices/invoice_parts_line_items_support.dart';
import 'package:vortice_app/features/invoices/invoice_export_context.dart';
import 'package:vortice_app/models/invoice.dart';

class InvoiceDetailLineItemsCard extends ConsumerWidget {
  final Invoice invoice;
  final bool showMxn;

  const InvoiceDetailLineItemsCard({
    super.key,
    required this.invoice,
    required this.showMxn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final labourTotal = invoice.labourTotalUsd ?? 0;
    final partLines = invoice.exportSnapshot == null
        ? const <InvoicePartLineItem>[]
        : buildInvoicePartLineItems(
            InvoiceExportContextService.fromSnapshot(invoice).invoiceParts,
          );
    final partsTotalUsd = invoice.partsTotalUsd ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.fromBorderSide(
          BorderSide(color: context.appColors.cardBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lineItems.toUpperCase(),
            style: TextStyle(
              color: context.appColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Divider(height: 20),
          InvoiceDetailLineItemRow(
            label: l10n.labour,
            detail:
                '${invoice.labourHours?.toStringAsFixed(1) ?? 0} hrs @ ${formatInvoiceCurrency(
                  convertInvoiceAmount(invoice.billableRateUsd, showMxn: showMxn, exchangeRate: invoice.exchangeRate),
                  mxn: showMxn,
                )}/hr',
            amount: formatInvoiceCurrency(
              convertInvoiceAmount(
                labourTotal,
                showMxn: showMxn,
                exchangeRate: invoice.exchangeRate,
              ),
              mxn: showMxn,
            ),
          ),
          const SizedBox(height: 12),
          if (partLines.isNotEmpty) ...[
            ...partLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InvoiceDetailLineItemRow(
                  label: formatInvoicePartLineLabel(line),
                  detail: formatInvoicePartLineDetail(
                    line,
                    spanish: isSpanish(context),
                    exchangeRate: showMxn ? (invoice.exchangeRate ?? 1) : 1,
                    currency: showMxn ? 'MXN' : 'USD',
                  ),
                  amount: formatInvoiceCurrency(
                    convertInvoiceAmount(
                      line.lineTotalUsd,
                      showMxn: showMxn,
                      exchangeRate: invoice.exchangeRate,
                    ),
                    mxn: showMxn,
                  ),
                ),
              ),
            ),
            if ((partsTotalUsd - sumInvoicePartLineTotals(partLines)).abs() >
                0.005)
              InvoiceDetailLineItemRow(
                label: isSpanish(context)
                    ? 'Ajuste de piezas'
                    : 'Parts adjustment',
                amount: formatInvoiceCurrency(
                  convertInvoiceAmount(
                    partsTotalUsd - sumInvoicePartLineTotals(partLines),
                    showMxn: showMxn,
                    exchangeRate: invoice.exchangeRate,
                  ),
                  mxn: showMxn,
                ),
              ),
            InvoiceDetailLineItemRow(
              label: l10n.partsWithMarkup,
              amount: formatInvoiceCurrency(
                convertInvoiceAmount(
                  partsTotalUsd,
                  showMxn: showMxn,
                  exchangeRate: invoice.exchangeRate,
                ),
                mxn: showMxn,
              ),
              isSubtle: true,
            ),
          ] else
            InvoiceDetailLineItemRow(
              label: l10n.partsWithMarkup,
              amount: formatInvoiceCurrency(
                convertInvoiceAmount(
                  invoice.partsTotalUsd,
                  showMxn: showMxn,
                  exchangeRate: invoice.exchangeRate,
                ),
                mxn: showMxn,
              ),
            ),
          const SizedBox(height: 12),
          InvoiceDetailLineItemRow(
            label: l10n.consumables,
            amount: formatInvoiceCurrency(
              convertInvoiceAmount(
                invoice.consumablesTotalUsd,
                showMxn: showMxn,
                exchangeRate: invoice.exchangeRate,
              ),
              mxn: showMxn,
            ),
            isSubtle: true,
          ),
        ],
      ),
    );
  }
}

class InvoiceDetailLineItemRow extends StatelessWidget {
  final String label;
  final String? detail;
  final String amount;
  final bool isSubtle;

  const InvoiceDetailLineItemRow({
    super.key,
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
                      ? context.appColors.textSecondary
                      : context.appColors.textPrimary,
                  fontSize: 14,
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: TextStyle(
                    color: context.appColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            color: isSubtle
                ? context.appColors.textSecondary
                : context.appColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class InvoiceDetailEditableLineItems extends StatelessWidget {
  final TextEditingController labourHoursCtrl;
  final TextEditingController billableRateCtrl;
  final TextEditingController partsTotalCtrl;
  final TextEditingController consumablesCtrl;
  final TextEditingController notesCtrl;

  const InvoiceDetailEditableLineItems({
    super.key,
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
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.fromBorderSide(
          BorderSide(color: context.appColors.cardBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.editLineItems.toUpperCase(),
            style: TextStyle(
              color: context.appColors.primary,
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
