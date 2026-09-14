import 'package:vortice_app/features/invoices/invoice_download.dart';
import 'package:vortice_app/features/invoices/invoice_detail_support.dart';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vortice_app/features/invoices/invoice_export_context.dart';
import 'package:vortice_app/features/invoices/invoice_parts_line_items_support.dart';
import 'package:vortice_app/models/invoice.dart';

/// Generates Excel (.xlsx) exports of invoices for accounting
class InvoiceExcelService {
  InvoiceExcelService._();

  static Future<void> generateAndShare(
    Invoice invoice, {
    bool spanish = false,
  }) async {
    final context = await InvoiceExportContextService.load(invoice);
    invoice = context.currentInvoice ?? invoice;
    final bytes = generateBytes(invoice, context: context, spanish: spanish);
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${invoice.invoiceNumber}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: invoice.invoiceNumber,
        text: invoice.invoiceNumber,
        fileNameOverrides: ['${invoice.invoiceNumber}.xlsx'],
      ),
    );
  }

  static Future<File?> downloadAndOpen(
    Invoice invoice, {
    bool spanish = false,
  }) async {
    final context = await InvoiceExportContextService.load(invoice);
    invoice = context.currentInvoice ?? invoice;
    final bytes = generateBytes(invoice, context: context, spanish: spanish);
    if (bytes == null) return null;

    final file = await writeInvoiceDownload(
      invoice,
      extension: 'xlsx',
      bytes: bytes,
    );
    await OpenFile.open(file.path);
    return file;
  }

  static List<int>? generateBytes(
    Invoice invoice, {
    InvoiceExportContext? context,
    bool spanish = false,
  }) {
    final excel = Excel.createExcel();

    // Create Invoice before deleting Sheet1. The excel package will not delete
    // the only sheet in a workbook, which leaves a blank first tab otherwise.
    final sheet = excel['Invoice'];
    excel.setDefaultSheet('Invoice');
    excel.delete('Sheet1');

    // Styles
    // Section header rows ("LINE ITEMS", "SUMMARY", main title)
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1E3A5F'),
      fontColorHex: ExcelColor.white,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Column header row ("Description", "Detail", "Amount (USD)")
    final colHeaderStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#D1D5DB'),
      fontColorHex: ExcelColor.fromHexString('#111827'),
    );

    // Left-column label cells ("Invoice Number:", "Status:", etc.)
    final labelStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#374151'),
    );

    // Right-column value cells (data values)
    final valueStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('#111827'),
    );

    // Amount/currency cells
    final currencyStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('#111827'),
      horizontalAlign: HorizontalAlign.Right,
    );

    // Total row
    final totalStyle = CellStyle(
      bold: true,
      fontSize: 12,
      backgroundColorHex: ExcelColor.fromHexString('#1E3A5F'),
      fontColorHex: ExcelColor.white,
      horizontalAlign: HorizontalAlign.Right,
    );

    // Total label style (left-aligned, same bg as total)
    final totalLabelStyle = CellStyle(
      bold: true,
      fontSize: 12,
      backgroundColorHex: ExcelColor.fromHexString('#1E3A5F'),
      fontColorHex: ExcelColor.white,
    );

    // Exchange rate row
    final exchangeRateStyle = CellStyle(
      fontColorHex: ExcelColor.fromHexString('#6B7280'),
      italic: true,
    );

    // Header
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('D1'));
    final headerCell = sheet.cell(CellIndex.indexByString('A1'));
    headerCell.value = TextCellValue(
      (spanish
          ? 'Vortice Mechanical - Factura'
          : 'Vortice Mechanical - Invoice'),
    );
    headerCell.cellStyle = headerStyle;

    // Invoice details
    int row = 3;

    void addLabelValue(String label, String value) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        label,
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .cellStyle =
          labelStyle;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(
        value,
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
              .cellStyle =
          valueStyle;
      row++;
    }

    addLabelValue(
      (spanish ? 'Número de factura:' : 'Invoice Number:'),
      invoice.invoiceNumber,
    );
    addLabelValue(
      (spanish ? 'Estado:' : 'Status:'),
      invoiceStatusLabel(invoice.status, spanish: spanish).toUpperCase(),
    );
    addLabelValue(
      (spanish ? 'Creada:' : 'Created:'),
      _formatDate(invoice.sentAt ?? invoice.createdAt),
    );
    if (invoice.paidAt != null) {
      addLabelValue(
        (spanish ? 'Pagada:' : 'Paid:'),
        _formatDate(invoice.paidAt),
      );
    }
    if (context != null) {
      addLabelValue(
        (spanish ? 'Facturar a:' : 'Bill To:'),
        context.billingLabel,
      );
      if (context.clientEmail != null) {
        addLabelValue(
          (spanish ? 'Correo del cliente:' : 'Client Email:'),
          context.clientEmail!,
        );
      }
      if (context.clientPhone != null) {
        addLabelValue(
          (spanish ? 'Teléfono del cliente:' : 'Client Phone:'),
          context.clientPhone!,
        );
      }
      addLabelValue(
        (spanish ? 'Orden de trabajo:' : 'Work Order:'),
        context.workOrderLabel,
      );
      addLabelValue((spanish ? 'Equipo:' : 'Asset:'), context.assetLabel);
    }

    row += 2;

    // Line items header
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
    );
    final itemsHeader = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    );
    itemsHeader.value = TextCellValue((spanish ? 'CONCEPTOS' : 'LINE ITEMS'));
    itemsHeader.cellStyle = headerStyle;
    row++;

    // Column headers
    final colHeaders = [
      (spanish ? 'Descripción' : 'Description'),
      (spanish ? 'Detalle' : 'Detail'),
      (spanish ? 'Importe (USD)' : 'Amount (USD)'),
      (spanish ? 'Importe (MXN)' : 'Amount (MXN)'),
      (spanish ? 'Importe (CAD)' : 'Amount (CAD)'),
    ];
    for (var i = 0; i < colHeaders.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
      );
      cell.value = TextCellValue(colHeaders[i]);
      cell.cellStyle = colHeaderStyle;
    }
    row++;

    final labourTotal =
        invoice.labourTotalUsd ??
        ((invoice.labourHours ?? 0) * (invoice.billableRateUsd ?? 0));
    final rate = invoice.exchangeRate ?? 1;

    void addLineItem(String desc, String? detail, double usd) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        desc,
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .cellStyle =
          valueStyle;
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
              .cellStyle =
          valueStyle;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(
        detail ?? '',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = DoubleCellValue(
        usd,
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
              .cellStyle =
          currencyStyle;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = DoubleCellValue(
        usd * rate,
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
              .cellStyle =
          currencyStyle;
      final cadCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
      );
      cadCell.value = invoice.cadExchangeRate == null
          ? TextCellValue('-')
          : DoubleCellValue(
              double.parse((usd * invoice.cadExchangeRate!).toStringAsFixed(2)),
            );
      cadCell.cellStyle = currencyStyle;
      row++;
    }

    addLineItem(
      (spanish ? 'Mano de obra' : 'Labour'),
      '${invoice.labourHours?.toStringAsFixed(1) ?? 0} hrs @ \$${invoice.billableRateUsd?.toStringAsFixed(2) ?? '0.00'}/hr',
      labourTotal,
    );
    final partLines = buildInvoicePartLineItems(
      context?.invoiceParts ?? const [],
    );
    if (partLines.isEmpty) {
      addLineItem(
        (spanish ? 'Piezas (con margen)' : 'Parts (with markup)'),
        null,
        invoice.partsTotalUsd ?? 0,
      );
    } else {
      for (final line in partLines) {
        addLineItem(
          formatInvoicePartLineLabel(line),
          formatInvoicePartLineDetail(line, spanish: spanish),
          line.lineTotalUsd,
        );
      }
      final adjustment =
          (invoice.partsTotalUsd ?? 0) - sumInvoicePartLineTotals(partLines);
      if (adjustment.abs() > 0.005) {
        addLineItem(
          (spanish ? 'Ajuste de piezas' : 'Parts adjustment'),
          null,
          adjustment,
        );
      }
    }
    addLineItem(
      (spanish ? 'Consumibles' : 'Consumables'),
      null,
      invoice.consumablesTotalUsd ?? 0,
    );

    row += 2;

    // Summary
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
    );
    final summaryHeader = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
    );
    summaryHeader.value = TextCellValue((spanish ? 'RESUMEN' : 'SUMMARY'));
    summaryHeader.cellStyle = headerStyle;
    row++;

    void addSummaryRow(String label, double usd, {bool isTotal = false}) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(
        label,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .cellStyle = isTotal
          ? totalStyle
          : labelStyle;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = DoubleCellValue(
        usd,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .cellStyle = isTotal
          ? totalStyle
          : currencyStyle;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = DoubleCellValue(
        usd * rate,
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .cellStyle = isTotal
          ? totalStyle
          : currencyStyle;
      final cadCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
      );
      cadCell.value = invoice.cadExchangeRate == null
          ? TextCellValue('-')
          : DoubleCellValue(
              double.parse((usd * invoice.cadExchangeRate!).toStringAsFixed(2)),
            );
      cadCell.cellStyle = currencyStyle;
      row++;
    }

    addSummaryRow('Subtotal', invoice.subtotalUsd ?? 0);
    addSummaryRow(
      '${spanish ? 'Impuesto' : 'Tax'} (${invoice.ivaPct}%)',
      invoice.ivaTotalUsd ?? 0,
    );

    // Total row — full-width highlight
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      (spanish ? 'TOTAL' : 'TOTAL DUE'),
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        totalLabelStyle;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
        .value = DoubleCellValue(
      invoice.totalUsd ?? 0,
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .cellStyle =
        totalStyle;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
        .value = DoubleCellValue(
      invoice.totalMxn ?? 0,
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .cellStyle =
        totalStyle;
    final cadTotal = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
    );
    cadTotal.value = invoice.totalCad == null
        ? TextCellValue('-')
        : DoubleCellValue(invoice.totalCad!);
    cadTotal.cellStyle = totalStyle;
    row++;

    row += 2;

    // Exchange rate
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue(
      '${spanish ? 'Tipo de cambio' : 'Exchange rate'}: 1 USD = ${invoice.exchangeRate?.toStringAsFixed(4) ?? '-'} MXN',
    );
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .cellStyle =
        exchangeRateStyle;

    row++;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
      ..value = TextCellValue(
        invoice.cadExchangeRate == null
            ? (spanish
                  ? 'CAD: sin tipo de cambio guardado'
                  : 'CAD: no saved exchange rate')
            : '1 USD = ${invoice.cadExchangeRate!.toStringAsFixed(6)} CAD',
      )
      ..cellStyle = exchangeRateStyle;
    sheet.setColumnWidth(4, 18);
    // Set column widths
    sheet.setColumnWidth(0, 25);
    sheet.setColumnWidth(1, 35);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 18);

    return excel.save();
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
