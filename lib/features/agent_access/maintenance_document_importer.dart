import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'maintenance_documents_repository.dart';

class MaintenanceDocumentImporter {
  Future<List<MaintenanceDocumentPage>> camera() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
      imageQuality: 90,
    );
    return file == null
        ? []
        : [MaintenanceDocumentPage(await file.readAsBytes())];
  }

  Future<List<MaintenanceDocumentPage>> photos() async {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 2400,
      imageQuality: 90,
      limit: 30,
    );
    return Future.wait(
      files.map(
        (file) async => MaintenanceDocumentPage(await file.readAsBytes()),
      ),
    );
  }

  Future<List<MaintenanceDocumentPage>> pdf() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'PDF',
          extensions: ['pdf'],
          mimeTypes: ['application/pdf'],
          uniformTypeIdentifiers: ['com.adobe.pdf'],
        ),
      ],
    );
    if (file == null) return [];
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('PDF is too large');
    }
    final bytes = await file.readAsBytes();
    final pages = <MaintenanceDocumentPage>[];
    var total = 0;
    // Render scanned and text PDFs alike; the vision agent sees the actual page.
    // Never silently truncate a manual and suggest that every page was read.
    await for (final raster in Printing.raster(bytes, dpi: 150)) {
      if (pages.length >= 30) {
        throw const FormatException('Choose a PDF with at most 30 pages');
      }
      final page = MaintenanceDocumentPage(await raster.toPng());
      total += page.bytes.length;
      if (total > 40 * 1024 * 1024) {
        throw const FormatException('Split this PDF into smaller sections');
      }
      pages.add(page);
    }
    if (pages.isEmpty) throw const FormatException('PDF has no pages');
    return pages;
  }

  Future<List<MaintenanceDocumentPage>> recover() async {
    if (!Platform.isAndroid) return [];
    final result = await ImagePicker().retrieveLostData();
    if (result.exception != null) throw result.exception!;
    return Future.wait(
      (result.files ?? <XFile>[]).map(
        (file) async => MaintenanceDocumentPage(await file.readAsBytes()),
      ),
    );
  }
}
