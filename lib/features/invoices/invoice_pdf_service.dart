import 'canadian_invoice.dart';
import 'canadian_invoice_exports.dart';
import 'package:vortice_app/features/invoices/invoice_download.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:printing/printing.dart';
import 'package:vortice_app/features/invoices/invoice_export_context.dart';
import 'package:vortice_app/features/invoices/invoice_parts_line_items_support.dart';
import 'package:vortice_app/models/invoice.dart';

/// Generates professional print-ready PDF invoices (white background, business layout)
class InvoicePdfService {
  InvoicePdfService._();

  // Palette — clean business print style
  static const _navy = PdfColor.fromInt(0xFF1E3A5F);
  static const _accent = PdfColor.fromInt(0xFF2563EB);
  static const _darkGrey = PdfColor.fromInt(0xFF374151);
  static const _midGrey = PdfColor.fromInt(0xFF6B7280);
  static const _lightGrey = PdfColor.fromInt(0xFFF3F4F6);
  static const _borderGrey = PdfColor.fromInt(0xFFD1D5DB);

  static Future<void> generateAndShare(
    Invoice invoice, {
    bool spanish = false,
    bool french = false,
  }) async {
    final exportContext = await InvoiceExportContextService.load(invoice);
    invoice = exportContext.currentInvoice ?? invoice;
    final bytes = await generateBytes(
      invoice,
      exportContext: exportContext,
      spanish: spanish,
      french: french,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${invoice.invoiceNumber}.pdf',
    );
  }

  static Future<File> downloadAndOpen(
    Invoice invoice, {
    bool spanish = false,
    bool french = false,
  }) async {
    final exportContext = await InvoiceExportContextService.load(invoice);
    invoice = exportContext.currentInvoice ?? invoice;
    final bytes = await generateBytes(
      invoice,
      exportContext: exportContext,
      spanish: spanish,
      french: french,
    );
    final file = await writeInvoiceDownload(
      invoice,
      extension: 'pdf',
      bytes: bytes,
    );
    await OpenFile.open(file.path);
    return file;
  }

  static Future<Uint8List> generateBytes(
    Invoice invoice, {
    InvoiceExportContext? exportContext,
    bool spanish = false,
    bool french = false,
  }) async {
    if (invoice.isNativeCad) {
      return canadianInvoicePdf(
        invoice,
        language: french
            ? 'fr'
            : spanish
            ? 'es'
            : 'en',
      );
    }
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(
          await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
        ),
        bold: pw.Font.ttf(
          await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
        ),
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        footer: (_) => pw.Column(
          children: [
            pw.Divider(color: _borderGrey),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Vortice Mechanical — Puerto Vallarta, Jalisco, Mexico',
                  style: const pw.TextStyle(color: _midGrey, fontSize: 8),
                ),
                pw.Text(
                  invoice.invoiceNumber,
                  style: const pw.TextStyle(color: _midGrey, fontSize: 8),
                ),
              ],
            ),
          ],
        ),
        build: (context) =>
            _buildPage(invoice, exportContext: exportContext, spanish: spanish),
      ),
    );

    return pdf.save();
  }

  static List<pw.Widget> _buildPage(
    Invoice invoice, {
    InvoiceExportContext? exportContext,
    bool spanish = false,
  }) {
    final labourTotal =
        invoice.labourTotalUsd ??
        ((invoice.labourHours ?? 0) * (invoice.billableRateUsd ?? 0));
    final subtotal = invoice.subtotalUsd ?? 0;
    final iva = invoice.ivaTotalUsd ?? 0;
    final totalUsd = invoice.totalUsd ?? 0;
    final totalMxn = invoice.totalMxn ?? 0;
    final partLines = buildInvoicePartLineItems(
      exportContext?.invoiceParts ?? const [],
    );

    return [
      // ── Company header ─────────────────────────────────────────
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Company info (left)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Vortice Mechanical',
                style: pw.TextStyle(
                  color: _navy,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                (spanish
                    ? 'Mantenimiento marino y de equipos pesados'
                    : 'Marine & Heavy Equipment Maintenance'),
                style: const pw.TextStyle(color: _midGrey, fontSize: 10),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Puerto Vallarta, Jalisco, Mexico',
                style: const pw.TextStyle(color: _midGrey, fontSize: 9),
              ),
            ],
          ),
          // Invoice label + number (right)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                (spanish ? 'FACTURA' : 'INVOICE'),
                style: pw.TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                invoice.invoiceNumber,
                style: pw.TextStyle(
                  color: _navy,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              _metaRow(
                (spanish ? 'Fecha de emisión' : 'Issue Date'),
                _formatDate(invoice.sentAt ?? invoice.createdAt),
              ),
              pw.SizedBox(height: 2),
              _metaRow(
                (spanish ? 'Estado' : 'Status'),
                invoiceStatusLabel(
                  invoice.status,
                  spanish: spanish,
                ).toUpperCase(),
              ),
              if (invoice.paidAt != null) ...[
                pw.SizedBox(height: 2),
                _metaRow(
                  (spanish ? 'Pagada' : 'Paid'),
                  _formatDate(invoice.paidAt),
                ),
              ],
            ],
          ),
        ],
      ),

      pw.SizedBox(height: 6),
      pw.Divider(color: _navy, thickness: 2),
      pw.SizedBox(height: 20),

      if (exportContext != null) ...[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _contextBlock((spanish ? 'FACTURAR A' : 'BILL TO'), [
                exportContext.billingLabel,
                if (exportContext.clientEmail != null)
                  exportContext.clientEmail!,
                if (exportContext.clientPhone != null)
                  exportContext.clientPhone!,
              ]),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: _contextBlock((spanish ? 'TRABAJO' : 'WORK'), [
                exportContext.workOrderLabel,
                exportContext.assetLabel,
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
      ],

      // ── Line items table ────────────────────────────────────────
      _sectionLabel((spanish ? 'CONCEPTOS' : 'LINE ITEMS')),
      pw.SizedBox(height: 6),
      pw.Table(
        border: const pw.TableBorder(
          bottom: pw.BorderSide(color: _borderGrey),
          horizontalInside: pw.BorderSide(color: _borderGrey, width: 0.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(1.5),
        },
        children: [
          // Header row
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _lightGrey),
            children: [
              _tableHeader((spanish ? 'Descripción' : 'Description')),
              _tableHeader((spanish ? 'Detalle' : 'Detail')),
              _tableHeader(
                (spanish ? 'Importe (USD)' : 'Amount (USD)'),
                align: pw.TextAlign.right,
              ),
            ],
          ),
          // Labour
          pw.TableRow(
            children: [
              _tableCell((spanish ? 'Mano de obra' : 'Labour')),
              _tableCell(
                '${invoice.labourHours?.toStringAsFixed(1) ?? '0'} hrs @ \$${invoice.billableRateUsd?.toStringAsFixed(2) ?? '0.00'}/hr',
                muted: true,
              ),
              _tableCell(
                '\$${labourTotal.toStringAsFixed(2)}',
                align: pw.TextAlign.right,
              ),
            ],
          ),
          ..._partsTableRows(invoice, partLines, spanish: spanish),
          // Consumables
          pw.TableRow(
            children: [
              _tableCell((spanish ? 'Consumibles' : 'Consumables')),
              _tableCell('—', muted: true),
              _tableCell(
                '\$${(invoice.consumablesTotalUsd ?? 0).toStringAsFixed(2)}',
                align: pw.TextAlign.right,
                muted: true,
              ),
            ],
          ),
        ],
      ),

      pw.SizedBox(height: 20),

      // ── Totals (right-aligned block) ────────────────────────────
      pw.Row(
        children: [
          pw.Spacer(),
          pw.Container(
            width: 240,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _lightGrey,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _borderGrey),
            ),
            child: pw.Column(
              children: [
                _totalRow('Subtotal', '\$${subtotal.toStringAsFixed(2)} USD'),
                pw.SizedBox(height: 4),
                _totalRow(
                  '${spanish ? 'Impuesto' : 'Tax'} (${invoice.ivaPct}%)',
                  '\$${iva.toStringAsFixed(2)} USD',
                ),
                pw.Divider(color: _borderGrey, height: 14),
                _totalRow(
                  (spanish ? 'Total (USD)' : 'Total Due (USD)'),
                  '\$${totalUsd.toStringAsFixed(2)}',
                  bold: true,
                  color: _navy,
                ),
                pw.SizedBox(height: 4),
                _totalRow(
                  (spanish ? 'Total (MXN)' : 'Total Due (MXN)'),
                  '\$${totalMxn.toStringAsFixed(2)}',
                  bold: true,
                  color: _accent,
                ),
                pw.SizedBox(height: 4),
                _totalRow(
                  (spanish ? 'Total (CAD)' : 'Total Due (CAD)'),
                  invoice.totalCad == null
                      ? '-'
                      : '\$${invoice.totalCad!.toStringAsFixed(2)}',
                  bold: true,
                  color: _accent,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  invoice.cadExchangeRate == null
                      ? (spanish
                            ? 'CAD: sin tipo de cambio guardado'
                            : 'CAD: no saved exchange rate')
                      : '1 USD = ${invoice.cadExchangeRate!.toStringAsFixed(6)} CAD',
                  style: const pw.TextStyle(color: _midGrey, fontSize: 8),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '${spanish ? 'Tipo de cambio' : 'Exchange rate'}: 1 USD = ${invoice.exchangeRate?.toStringAsFixed(4) ?? '-'} MXN',
                  style: const pw.TextStyle(color: _midGrey, fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),

      // ── Notes ───────────────────────────────────────────────────
      if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
        pw.SizedBox(height: 20),
        _sectionLabel((spanish ? 'NOTAS' : 'NOTES')),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borderGrey),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            invoice.notes!,
            style: const pw.TextStyle(color: _darkGrey, fontSize: 10),
          ),
        ),
      ],
    ];
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static List<pw.TableRow> _partsTableRows(
    Invoice invoice,
    List<InvoicePartLineItem> partLines, {
    bool spanish = false,
  }) {
    if (partLines.isEmpty) {
      return [
        pw.TableRow(
          children: [
            _tableCell(
              (spanish ? 'Piezas (con margen)' : 'Parts (with markup)'),
            ),
            _tableCell('—', muted: true),
            _tableCell(
              '\$${(invoice.partsTotalUsd ?? 0).toStringAsFixed(2)}',
              align: pw.TextAlign.right,
            ),
          ],
        ),
      ];
    }

    final rows = partLines
        .map(
          (line) => pw.TableRow(
            children: [
              _tableCell(formatInvoicePartLineLabel(line)),
              _tableCell(
                formatInvoicePartLineDetail(line, spanish: spanish),
                muted: true,
              ),
              _tableCell(
                '\$${line.lineTotalUsd.toStringAsFixed(2)}',
                align: pw.TextAlign.right,
              ),
            ],
          ),
        )
        .toList();

    final adjustment =
        (invoice.partsTotalUsd ?? 0) - sumInvoicePartLineTotals(partLines);
    if (adjustment.abs() > 0.005) {
      rows.add(
        pw.TableRow(
          children: [
            _tableCell((spanish ? 'Ajuste de piezas' : 'Parts adjustment')),
            _tableCell(''),
            _tableCell(
              '\$${adjustment.toStringAsFixed(2)}',
              align: pw.TextAlign.right,
            ),
          ],
        ),
      );
    }
    rows.add(
      pw.TableRow(
        children: [
          _tableCell(
            (spanish ? 'Piezas (con margen)' : 'Parts (with markup)'),
            muted: true,
          ),
          _tableCell('Total', muted: true),
          _tableCell(
            '\$${(invoice.partsTotalUsd ?? 0).toStringAsFixed(2)}',
            align: pw.TextAlign.right,
            muted: true,
          ),
        ],
      ),
    );

    return rows;
  }

  static pw.Widget _metaRow(String label, String value) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          '$label: ',
          style: const pw.TextStyle(color: _midGrey, fontSize: 9),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: _darkGrey,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _sectionLabel(String text) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        color: _navy,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  static pw.Widget _contextBlock(String title, List<String> lines) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(title),
        pw.SizedBox(height: 5),
        ...lines.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              line,
              style: const pw.TextStyle(color: _darkGrey, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableHeader(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: _navy,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    bool muted = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: muted ? _midGrey : _darkGrey, fontSize: 10),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
    PdfColor? color,
  }) {
    final style = pw.TextStyle(
      fontSize: bold ? 12 : 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? _darkGrey,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(value, style: style),
      ],
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
