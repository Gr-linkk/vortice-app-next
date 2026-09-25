import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/models/invoice.dart';

String billingText(BuildContext context, String en, String es, String fr) =>
    switch (Localizations.localeOf(context).languageCode) {
      'fr' => fr,
      'es' => es,
      _ => en,
    };

extension CanadianInvoice on Invoice {
  bool get isNativeCad => billingCurrency == 'CAD';
  double get nativeTotal => isNativeCad ? totalCad ?? 0 : totalUsd ?? 0;
  Map<String, dynamic> get cadDetails => billingDetails ?? const {};
}

typedef InvoiceDocumentRow = ({String label, String value});

/// One saved document projection shared by the phone, PDF and spreadsheet.
/// Values are server-calculated; exports never calculate tax or exchange rates.
List<InvoiceDocumentRow> canadianInvoiceRows(
  Invoice invoice, {
  String language = 'en',
}) {
  final d = invoice.cadDetails;
  final issuer = Map<String, dynamic>.from(d['issuer'] as Map? ?? {});
  String t(String en, String es, String fr) => switch (language) {
    'es' => es,
    'fr' => fr,
    _ => en,
  };
  String money(dynamic value) {
    final amount = value as num? ?? 0;
    return '${language == 'fr' ? NumberFormat('#,##0.00', 'fr_CA').format(amount) : amount.toStringAsFixed(2)} CAD';
  }

  String number(dynamic value) => language == 'fr'
      ? NumberFormat('0.####', 'fr_CA').format(value as num? ?? 0)
      : '$value';
  final taxes = (d['taxes'] as List? ?? []).cast<Map>();
  return [
    (
      label: t('Issuer', 'Emisor', 'Émetteur'),
      value: '${issuer['legal_name'] ?? ''}',
    ),
    (
      label: t('Address', 'Dirección', 'Adresse'),
      value: '${issuer['address'] ?? ''}',
    ),
    (
      label: t('Contact', 'Contacto', 'Coordonnées'),
      value: '${issuer['contact'] ?? ''}',
    ),
    (
      label: t('Tax registration', 'Registro fiscal', 'Inscription fiscale'),
      value: issuer['registration_status'] == 'registered'
          ? '${issuer['tax_registration']}'
          : t('Not registered', 'No registrado', 'Non inscrit'),
    ),
    (
      label: t('Bill to', 'Facturar a', 'Facturer à'),
      value: '${d['customer_name'] ?? ''}',
    ),
    (
      label: t(
        'Customer address',
        'Dirección del cliente',
        'Adresse du client',
      ),
      value: '${d['customer_address'] ?? ''}',
    ),
    (
      label: t('Work supplied', 'Trabajo realizado', 'Travaux fournis'),
      value: '${d['supply_description'] ?? ''}',
    ),
    (
      label: t(
        'Province of supply',
        'Provincia del suministro',
        'Province de fourniture',
      ),
      value: '${d['supply_province'] ?? ''}',
    ),
    (
      label: t('Invoice date', 'Fecha de factura', 'Date de facturation'),
      value: '${d['issue_date'] ?? ''}',
    ),
    (
      label: t('Due date', 'Vencimiento', 'Date d’échéance'),
      value: '${d['due_date'] ?? ''}',
    ),
    (
      label: t('Payment terms', 'Condiciones de pago', 'Modalités de paiement'),
      value: '${d['payment_terms'] ?? ''}',
    ),
    (
      label: t('Labour', 'Mano de obra', 'Main-d’œuvre'),
      value:
          '${number(invoice.labourHours ?? 0)} h × ${money(d['labour_rate'])} = ${money(d['labour_total'])}',
    ),
    (
      label: t('Parts charge', 'Cargo de repuestos', 'Pièces facturées'),
      value: money(d['parts_total']),
    ),
    (
      label: t('Subtotal', 'Subtotal', 'Sous-total'),
      value: money(d['subtotal']),
    ),
    for (final tax in taxes)
      (
        label: '${tax['name']} (${number(tax['rate'])}%)',
        value:
            '${t('Base', 'Base', 'Assiette')} ${money(tax['base'])} : ${money(tax['amount'])}',
      ),
    (
      label: t('Tax treatment', 'Tratamiento fiscal', 'Traitement fiscal'),
      value: switch (d['tax_treatment']) {
        'taxable' => t('Taxable', 'Gravado', 'Taxable'),
        'zero_rated' => t('Zero-rated', 'Tasa cero', 'Détaxé'),
        'exempt' => t('Exempt', 'Exento', 'Exonéré'),
        _ => t('Not registered', 'No registrado', 'Non inscrit'),
      },
    ),
    (
      label: t('Tax review', 'Revisión fiscal', 'Vérification fiscale'),
      value: '${d['tax_review_note'] ?? ''}',
    ),
    (
      label: t('Total due', 'Total a pagar', 'Total à payer'),
      value: money(invoice.totalCad),
    ),
  ];
}

class CanadianInvoiceSummary extends StatelessWidget {
  const CanadianInvoiceSummary({super.key, required this.invoice});
  final Invoice invoice;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in canadianInvoiceRows(
        invoice,
        language: Localizations.localeOf(context).languageCode,
      ))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.label, style: Theme.of(context).textTheme.labelLarge),
              SelectableText(row.value),
            ],
          ),
        ),
    ],
  );
}
