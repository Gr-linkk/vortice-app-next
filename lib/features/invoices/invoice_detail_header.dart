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
                  color: invoiceStatusColor(invoice.status)
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  invoice.status.name.toUpperCase(),
                  style: TextStyle(
                    color: invoiceStatusColor(invoice.status),
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
              InvoiceDetailMetaItem(
                label: 'Created',
                value: formatInvoiceDate(invoice.createdAt),
              ),
              if (invoice.paidAt != null)
                InvoiceDetailMetaItem(
                  label: 'Paid',
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
