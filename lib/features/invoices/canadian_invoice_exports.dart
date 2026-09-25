import 'package:flutter/services.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vortice_app/models/invoice.dart';
import 'canadian_invoice.dart';

String _status(Invoice invoice, String language) =>
    switch ((invoice.status, language)) {
      (InvoiceStatus.draft, 'fr') => 'BROUILLON · Non émis',
      (InvoiceStatus.draft, 'es') => 'BORRADOR · No emitida',
      (InvoiceStatus.draft, _) => 'DRAFT · Not issued',
      (InvoiceStatus.voided, 'fr') => 'ANNULÉE',
      (InvoiceStatus.voided, 'es') => 'ANULADA',
      (InvoiceStatus.voided, _) => 'VOID',
      (InvoiceStatus.paid, 'fr') => 'PAYÉE',
      (InvoiceStatus.paid, 'es') => 'PAGADA',
      (InvoiceStatus.paid, _) => 'PAID',
      (_, 'fr') => 'ÉMISE',
      (_, 'es') => 'EMITIDA',
      _ => 'ISSUED',
    };

// Bound each unbreakable block so long notes cannot orphan a label or paint
// through a repeated page header. Blank paragraph spacing is normalized in PDF.
List<String> _pdfChunks(String value) {
  final chunks = <String>[];
  for (final raw in value.split('\n')) {
    var line = raw.trim();
    while (line.length > 360) {
      final space = line.lastIndexOf(' ', 360);
      final split = space > 180 ? space : 360;
      chunks.add(line.substring(0, split));
      line = line.substring(split).trimLeft();
    }
    if (line.isNotEmpty) chunks.add(line);
  }
  if (chunks.isEmpty) return [''];
  final result = <String>[];
  var block = '';
  var lines = 0;
  for (final chunk in chunks) {
    if (block.isNotEmpty && (block.length + chunk.length > 600 || lines >= 8)) {
      result.add(block);
      block = '';
      lines = 0;
    }
    block = block.isEmpty ? chunk : '$block\n$chunk';
    lines++;
  }
  if (block.isNotEmpty) result.add(block);
  return result;
}

Future<Uint8List> canadianInvoicePdf(
  Invoice invoice, {
  String language = 'en',
}) async {
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      ),
      bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
    ),
  );
  final rows = canadianInvoiceRows(invoice, language: language);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      maxPages: 100,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${language == 'fr'
                ? 'FACTURE'
                : language == 'es'
                ? 'FACTURA'
                : 'INVOICE'} · CAD',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xff123d3c),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(invoice.invoiceNumber),
          pw.Text(_status(invoice, language)),
          pw.Divider(),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${invoice.invoiceNumber} · ${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (_) => [
        for (final row in rows)
          for (final chunk in _pdfChunks(row.value))
            pw.Inseparable(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      row.label,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9,
                        color: const PdfColor.fromInt(0xff123d3c),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(chunk, style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
        if (invoice.voidReason != null)
          pw.Text(
            '${language == 'fr'
                ? 'Motif'
                : language == 'es'
                ? 'Motivo'
                : 'Reason'}: ${invoice.voidReason}',
          ),
      ],
    ),
  );
  return pdf.save();
}

List<int>? canadianInvoiceExcel(Invoice invoice, {String language = 'en'}) {
  final excel = Excel.createExcel();
  final sheet = excel['Invoice'];
  excel.setDefaultSheet('Invoice');
  excel.delete('Sheet1');
  sheet.setColumnWidth(0, 30);
  sheet.setColumnWidth(1, 85);
  sheet.appendRow([
    TextCellValue(invoice.invoiceNumber),
    TextCellValue('CAD · ${_status(invoice, language)}'),
  ]);
  for (final row in canadianInvoiceRows(invoice, language: language)) {
    sheet.appendRow([TextCellValue(row.label), TextCellValue(row.value)]);
  }
  // Numeric amounts support accounting imports without parsing formatted text.
  final d = invoice.cadDetails;
  final amounts = excel['CAD amounts'];
  amounts.setColumnWidth(0, 30);
  amounts.setColumnWidth(1, 24);
  for (final key in [
    'labour_rate',
    'labour_total',
    'parts_total',
    'subtotal',
    'tax_total',
    'total',
  ]) {
    amounts.appendRow([
      TextCellValue(key),
      DoubleCellValue((d[key] as num).toDouble()),
      TextCellValue('CAD'),
    ]);
  }
  for (final raw in d['taxes'] as List) {
    final tax = raw as Map;
    amounts.appendRow([
      TextCellValue(tax['name'] as String),
      DoubleCellValue((tax['amount'] as num).toDouble()),
      TextCellValue('CAD'),
      DoubleCellValue((tax['rate'] as num).toDouble()),
      DoubleCellValue((tax['base'] as num).toDouble()),
    ]);
  }
  if (invoice.voidReason != null) {
    sheet.appendRow([
      TextCellValue(
        language == 'fr'
            ? 'Motif'
            : language == 'es'
            ? 'Motivo'
            : 'Reason',
      ),
      TextCellValue(invoice.voidReason!),
    ]);
  }
  for (var row = 0; row < sheet.maxRows; row++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = CellStyle(
      bold: true,
      textWrapping: TextWrapping.WrapText,
      verticalAlign: VerticalAlign.Top,
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .cellStyle = CellStyle(
      textWrapping: TextWrapping.WrapText,
      verticalAlign: VerticalAlign.Top,
    );
  }
  return excel.encode();
}
