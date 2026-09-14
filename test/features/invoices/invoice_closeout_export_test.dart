import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/invoices/invoice_export_context.dart';
import 'package:vortice_app/features/invoices/invoice_pdf_service.dart';
import 'package:vortice_app/features/invoices/invoice_excel_service.dart';
import 'package:vortice_app/models/invoice.dart';
import 'package:vortice_app/models/part.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'long issued invoice exports in both languages with original snapshot and adjustment',
    () async {
      final invoice = Invoice(
        id: 'test',
        workOrderId: 'work',
        clientId: 'client',
        invoiceNumber: 'INV-20260907-EXAMPLE',
        status: InvoiceStatus.sent,
        labourHours: 2,
        billableRateUsd: 70,
        labourTotalUsd: 140,
        partsTotalUsd: 950,
        consumablesTotalUsd: 7,
        subtotalUsd: 1097,
        ivaPct: 16,
        ivaTotalUsd: 175.52,
        totalUsd: 1272.52,
        exchangeRate: 17.5,
        totalMxn: 22269.1,
        cadExchangeRate: 1.375,
        totalCad: 1749.72,
        createdAt: DateTime(2026, 9, 6),
        sentAt: DateTime(2026, 9, 7),
      );
      final context = InvoiceExportContext(
        clientName: 'Example fleet',
        workOrderTitle: 'Scheduled repair',
        assetName: 'Example machine',
        invoiceParts: [
          for (var i = 0; i < 90; i++)
            Part(
              id: 'part-$i',
              workOrderId: 'work',
              description: 'Replacement filter ${i + 1}',
              quantity: 1,
              unitCost: 10,
              markupPct: 0,
            ),
        ],
      );
      for (final spanish in [false, true]) {
        final bytes = await InvoicePdfService.generateBytes(
          invoice,
          exportContext: context,
          spanish: spanish,
        );
        expect(bytes.length, greaterThan(1000));
        final excel = InvoiceExcelService.generateBytes(
          invoice,
          context: context,
          spanish: spanish,
        )!;
        final cells = Excel.decodeBytes(excel)['Invoice'].rows
            .expand((r) => r)
            .map((c) => c?.value?.toString())
            .toList();
        expect(
          cells,
          contains(spanish ? 'Ajuste de piezas' : 'Parts adjustment'),
        );
        expect(cells, contains(spanish ? 'EMITIDA' : 'ISSUED'));
        expect(cells, contains(spanish ? 'Importe (CAD)' : 'Amount (CAD)'));
        expect(cells, contains('1749.72'));
        expect(cells, contains('1 USD = 1.375000 CAD'));
        final out = Platform.environment['VORTICE_INVOICE_CAPTURE'];
        if (out != null) {
          await Directory(out).create(recursive: true);
          await File(
            '$out/invoice-${spanish ? 'es' : 'en'}.pdf',
          ).writeAsBytes(bytes);
          await File(
            '$out/invoice-${spanish ? 'es' : 'en'}.xlsx',
          ).writeAsBytes(excel);
        }
      }
    },
  );
}
