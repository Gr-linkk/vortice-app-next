import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
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

  static Future<void> generateAndShare(Invoice invoice) async {
    final exportContext = await InvoiceExportContextService.load(invoice);
    final bytes = await generateBytes(invoice, exportContext: exportContext);

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${invoice.invoiceNumber}.pdf',
    );
  }

  static Future<File> downloadAndOpen(Invoice invoice) async {
    final exportContext = await InvoiceExportContextService.load(invoice);
    final bytes = await generateBytes(invoice, exportContext: exportContext);
    final file = await _writeDownloadFile(
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
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        build: (context) => _buildPage(invoice, exportContext: exportContext),
      ),
    );

    return pdf.save();
  }

  static Future<File> _writeDownloadFile(
    Invoice invoice, {
    required String extension,
    required List<int> bytes,
  }) async {
    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final invoiceDir = Directory('${dir.path}/Vortice Invoices');
    await invoiceDir.create(recursive: true);
    final file = File('${invoiceDir.path}/${invoice.invoiceNumber}.$extension');
    return file.writeAsBytes(bytes, flush: true);
  }

  static pw.Widget _buildPage(
    Invoice invoice, {
    InvoiceExportContext? exportContext,
  }) {
    final labourTotal =
        (invoice.labourHours ?? 0) * (invoice.billableRateUsd ?? 0);
    final subtotal = invoice.subtotalUsd ?? 0;
    final iva = invoice.ivaTotalUsd ?? 0;
    final totalUsd = invoice.totalUsd ?? 0;
    final totalMxn = invoice.totalMxn ?? 0;
    final partLines = buildInvoicePartLineItems(
      exportContext?.invoiceParts ?? const [],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
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
                  'Marine & Heavy Equipment Maintenance',
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
                  'INVOICE',
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
                _metaRow('Issue Date', _formatDate(invoice.createdAt)),
                pw.SizedBox(height: 2),
                _metaRow('Status', invoice.status.name.toUpperCase()),
                if (invoice.paidAt != null) ...[
                  pw.SizedBox(height: 2),
                  _metaRow('Paid', _formatDate(invoice.paidAt)),
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
                child: _contextBlock(
                  'BILL TO',
                  [
                    exportContext.billingLabel,
                    if (exportContext.clientEmail != null)
                      exportContext.clientEmail!,
                    if (exportContext.clientPhone != null)
                      exportContext.clientPhone!,
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: _contextBlock(
                  'WORK',
                  [
                    exportContext.workOrderLabel,
                    exportContext.assetLabel,
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
        ],

        // ── Line items table ────────────────────────────────────────
        _sectionLabel('LINE ITEMS'),
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
                _tableHeader('Description'),
                _tableHeader('Detail'),
                _tableHeader('Amount (USD)', align: pw.TextAlign.right),
              ],
            ),
            // Labour
            pw.TableRow(children: [
              _tableCell('Labour'),
              _tableCell(
                '${invoice.labourHours?.toStringAsFixed(1) ?? '0'} hrs @ \$${invoice.billableRateUsd?.toStringAsFixed(2) ?? '0.00'}/hr',
                muted: true,
              ),
              _tableCell('\$${labourTotal.toStringAsFixed(2)}',
                  align: pw.TextAlign.right),
            ]),
            ..._partsTableRows(invoice, partLines),
            // Consumables
            pw.TableRow(children: [
              _tableCell('Consumables (5%)'),
              _tableCell('—', muted: true),
              _tableCell(
                  '\$${(invoice.consumablesTotalUsd ?? 0).toStringAsFixed(2)}',
                  align: pw.TextAlign.right,
                  muted: true),
            ]),
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
                  _totalRow('IVA (${invoice.ivaPct.toStringAsFixed(0)}%)',
                      '\$${iva.toStringAsFixed(2)} USD'),
                  pw.Divider(color: _borderGrey, height: 14),
                  _totalRow(
                    'Total Due (USD)',
                    '\$${totalUsd.toStringAsFixed(2)}',
                    bold: true,
                    color: _navy,
                  ),
                  pw.SizedBox(height: 4),
                  _totalRow(
                    'Total Due (MXN)',
                    '\$${totalMxn.toStringAsFixed(2)}',
                    bold: true,
                    color: _accent,
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Exchange rate: 1 USD = ${invoice.exchangeRate?.toStringAsFixed(4) ?? '-'} MXN',
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
          _sectionLabel('NOTES'),
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

        pw.Spacer(),

        // ── Footer ──────────────────────────────────────────────────
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
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static List<pw.TableRow> _partsTableRows(
    Invoice invoice,
    List<InvoicePartLineItem> partLines,
  ) {
    if (partLines.isEmpty) {
      return [
        pw.TableRow(children: [
          _tableCell('Parts (with markup)'),
          _tableCell('—', muted: true),
          _tableCell('\$${(invoice.partsTotalUsd ?? 0).toStringAsFixed(2)}',
              align: pw.TextAlign.right),
        ]),
      ];
    }

    final rows = partLines
        .map(
          (line) => pw.TableRow(children: [
            _tableCell(formatInvoicePartLineLabel(line)),
            _tableCell(formatInvoicePartLineDetail(line), muted: true),
            _tableCell('\$${line.lineTotalUsd.toStringAsFixed(2)}',
                align: pw.TextAlign.right),
          ]),
        )
        .toList();

    rows.add(
      pw.TableRow(children: [
        _tableCell('Parts (with markup)', muted: true),
        _tableCell('Total', muted: true),
        _tableCell(
          '\$${sumInvoicePartLineTotals(partLines).toStringAsFixed(2)}',
          align: pw.TextAlign.right,
          muted: true,
        ),
      ]),
    );

    return rows;
  }

  static pw.Widget _metaRow(String label, String value) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text('$label: ',
            style: const pw.TextStyle(color: _midGrey, fontSize: 9)),
        pw.Text(value,
            style: pw.TextStyle(
                color: _darkGrey, fontSize: 9, fontWeight: pw.FontWeight.bold)),
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
      crossAxisAlignment: pw.CrossAxisAlignment.start,
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

  static pw.Widget _tableHeader(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
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

  static pw.Widget _tableCell(String text,
      {pw.TextAlign align = pw.TextAlign.left, bool muted = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: muted ? _midGrey : _darkGrey, fontSize: 10),
        textAlign: align,
      ),
    );
  }

  static pw.Widget _totalRow(String label, String value,
      {bool bold = false, PdfColor? color}) {
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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
