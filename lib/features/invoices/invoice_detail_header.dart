import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'package:vortice_app/models/invoice.dart';

class InvoiceDetailHeader extends StatelessWidget {
  final Invoice invoice;

  const InvoiceDetailHeader({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [context.appColors.surfaceVariant, context.appColors.surface],
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
              Text(
                isSpanish(context) ? 'FACTURA' : 'INVOICE',
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: invoiceStatusColor(
                    context.appColors,
                    invoice.status,
                  ).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  invoiceStatusLabel(
                    invoice.status,
                    spanish: isSpanish(context),
                  ).toUpperCase(),
                  style: TextStyle(
                    color: invoiceStatusColor(
                      context.appColors,
                      invoice.status,
                    ),
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
            style: TextStyle(
              color: context.appColors.primary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              InvoiceDetailMetaItem(
                label: isSpanish(context) ? 'Creada' : 'Created',
                value: formatInvoiceDate(invoice.createdAt),
              ),
              if (invoice.paidAt != null)
                InvoiceDetailMetaItem(
                  label: isSpanish(context) ? 'Pagada' : 'Paid',
                  value: formatInvoiceDate(invoice.paidAt),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class InvoiceDetailMetaItem extends StatelessWidget {
  final String label;
  final String value;

  const InvoiceDetailMetaItem({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13),
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: context.appColors.textSecondary),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: context.appColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
