import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:vortice_app/features/invoices/invoice_download.dart';
import 'package:vortice_app/models/invoice.dart';

class _Directories extends PathProviderPlatform {
  _Directories(this.path, this.downloadsAvailable);
  final String path;
  final bool downloadsAvailable;
  bool usedDocuments = false;

  @override
  Future<String?> getDownloadsPath() async => downloadsAvailable ? path : null;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    usedDocuments = true;
    return path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final downloadsAvailable in [true, false]) {
    test(
      'invoice files retain names and bytes; Downloads=$downloadsAvailable',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'invoice-download-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final previous = PathProviderPlatform.instance;
        final directories = _Directories(directory.path, downloadsAvailable);
        PathProviderPlatform.instance = directories;
        addTearDown(() => PathProviderPlatform.instance = previous);
        const invoice = Invoice(
          id: 'invoice',
          workOrderId: 'work',
          clientId: 'client',
          invoiceNumber: 'INV-25',
          status: InvoiceStatus.sent,
        );
        for (final extension in ['pdf', 'xlsx']) {
          final file = await writeInvoiceDownload(
            invoice,
            extension: extension,
            bytes: [1, 2, 255],
          );
          expect(
            file.path,
            '${directory.path}/Vortice Invoices/INV-25.$extension',
          );
          expect(await file.readAsBytes(), [1, 2, 255]);
          await writeInvoiceDownload(invoice, extension: extension, bytes: [7]);
          expect(await file.readAsBytes(), [7]);
        }
        expect(directories.usedDocuments, !downloadsAvailable);
      },
    );
  }
}
