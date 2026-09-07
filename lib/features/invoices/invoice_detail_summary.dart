import 'package:flutter/material.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/models/invoice.dart';

class InvoiceDetailSummaryCard extends StatelessWidget {
  final Invoice invoice;
  final bool showMxn;

  const InvoiceDetailSummaryCard({
    super.key,
    required this.invoice,
    required this.showMxn,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.fromBorderSide(
          BorderSide(color: context.appColors.cardBorder),
        ),
      ),
      child: Column(
        children: [
          InvoiceDetailSummaryRow(
            label: l10n.subtotal,
            value: formatInvoiceCurrency(
              convertInvoiceAmount(
                invoice.subtotalUsd,
                showMxn: showMxn,
                exchangeRate: invoice.exchangeRate,
              ),
              mxn: showMxn,
            ),
          ),
          InvoiceDetailSummaryRow(
            label: 'IVA (${invoice.ivaPct.toStringAsFixed(0)}%)',
            value: formatInvoiceCurrency(
              convertInvoiceAmount(
                invoice.ivaTotalUsd,
                showMxn: showMxn,
                exchangeRate: invoice.exchangeRate,
              ),
              mxn: showMxn,
            ),
          ),
          Divider(color: context.appColors.divider, height: 24),
          InvoiceDetailSummaryRow(
            label: l10n.totalDue,
            value: showMxn
                ? formatInvoiceCurrency(invoice.totalMxn, mxn: true)
                : formatInvoiceCurrency(invoice.totalUsd, mxn: false),
            isGrand: true,
          ),
          if (!showMxn && invoice.totalMxn != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '(${formatInvoiceCurrency(invoice.totalMxn, mxn: true)})',
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          if (invoice.exchangeRate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${l10n.exchangeRate}: 1 USD = ${invoice.exchangeRate!.toStringAsFixed(4)} MXN',
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class InvoiceDetailSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isGrand;

  const InvoiceDetailSummaryRow({
    super.key,
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
              color: isGrand
                  ? context.appColors.primary
                  : context.appColors.textSecondary,
              fontSize: isGrand ? 18 : 14,
              fontWeight: isGrand ? FontWeight.w900 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isGrand
                  ? context.appColors.primary
                  : context.appColors.textPrimary,
              fontSize: isGrand ? 20 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
