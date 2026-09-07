import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vortice_app/models/invoice.dart';

Future<File> writeInvoiceDownload(
  Invoice invoice, {
  required String extension,
  required List<int> bytes,
}) async {
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final invoiceDir = Directory('${dir.path}/Vortice Invoices');
  await invoiceDir.create(recursive: true);
  final file = File('${invoiceDir.path}/${invoice.invoiceNumber}.$extension');
  return file.writeAsBytes(bytes, flush: true);
}
