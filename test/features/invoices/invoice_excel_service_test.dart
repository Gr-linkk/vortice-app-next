import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/invoices/invoice_export_context.dart';
import 'package:vortice_app/features/invoices/invoice_excel_service.dart';
import 'package:vortice_app/models/invoice.dart';

void main() {
  group('InvoiceExcelService', () {
    test('exports one invoice sheet as the default sheet', () {
      final bytes = InvoiceExcelService.generateBytes(
        Invoice(
          id: 'invoice-1',
          workOrderId: 'wo-1',
          clientId: 'client-1',
          invoiceNumber: 'INV-20260613-200000-001',
          status: InvoiceStatus.draft,
          labourHours: 2,
          billableRateUsd: 125,
          partsTotalUsd: 50,
          consumablesTotalUsd: 12.5,
          subtotalUsd: 312.5,
          ivaPct: 16,
          ivaTotalUsd: 50,
          totalUsd: 362.5,
          exchangeRate: 18.5,
          totalMxn: 6706.25,
          createdAt: DateTime(2026, 6, 13),
        ),
        context: const InvoiceExportContext(
          clientName: 'Paradise Marina',
          clientEmail: 'billing@example.com',
          workOrderTitle: 'Hydraulic leak repair',
          assetName: 'Dredge 1',
          assetMakeModel: 'Ellicott 460SL',
          assetSerialNumber: 'DR-460',
        ),
      );

      expect(bytes, isNotNull);

      final workbook = Excel.decodeBytes(bytes!);

      expect(workbook.tables.keys, ['Invoice']);
      expect(workbook.getDefaultSheet(), 'Invoice');

      final invoiceSheet = workbook['Invoice'];
      expect(
        invoiceSheet.cell(CellIndex.indexByString('A1')).value?.toString(),
        'Vortice Mechanical - Invoice',
      );
      expect(
        invoiceSheet.cell(CellIndex.indexByString('B4')).value?.toString(),
        'INV-20260613-200000-001',
      );
      expect(
        invoiceSheet.cell(CellIndex.indexByString('B7')).value?.toString(),
        'Paradise Marina',
      );
      expect(
        invoiceSheet.cell(CellIndex.indexByString('B8')).value?.toString(),
        'billing@example.com',
      );
      expect(
        invoiceSheet.cell(CellIndex.indexByString('B9')).value?.toString(),
        'Hydraulic leak repair',
      );
      expect(
        invoiceSheet.cell(CellIndex.indexByString('B10')).value?.toString(),
        'Dredge 1 - Ellicott 460SL - S/N DR-460',
      );
    });
  });
}
