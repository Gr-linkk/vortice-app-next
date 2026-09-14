import 'package:flutter/material.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/models/invoice.dart';

class InvoiceDetailSummaryCard extends StatelessWidget {
  final Invoice invoice;
  final InvoiceCurrency currency;

  const InvoiceDetailSummaryCard({
    super.key,
    required this.invoice,
    required this.currency,
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
            value: currency.amount(invoice.subtotalUsd, invoice),
          ),
          InvoiceDetailSummaryRow(
            label:
                '${Localizations.localeOf(context).languageCode == 'es' ? 'Impuesto' : 'Tax'} (${invoice.ivaPct}%)',
            value: currency.amount(invoice.ivaTotalUsd, invoice),
          ),
          Divider(color: context.appColors.divider, height: 24),
          InvoiceDetailSummaryRow(
            label: l10n.totalDue,
            value: formatInvoiceCurrency(
              currency.total(invoice),
              currency: currency,
            ),
            isGrand: true,
          ),
          for (final other in InvoiceCurrency.values.where(
            (v) => v != currency && v.total(invoice) != null,
          ))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                formatInvoiceCurrency(other.total(invoice), currency: other),
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          for (final other in [InvoiceCurrency.mxn, InvoiceCurrency.cad])
            if (other.rate(invoice) != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${l10n.exchangeRate}: 1 USD = ${other.rate(invoice)!.toStringAsFixed(other == InvoiceCurrency.cad ? 6 : 4)} ${other.code}',
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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 4,
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
