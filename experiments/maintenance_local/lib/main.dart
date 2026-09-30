import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'lab_bootstrap.dart';
import 'app.dart';
import 'src/rust/frb_generated.dart';
export 'app.dart';
export 'ui/workspace_page.dart';
export 'ui/inspection_page.dart';
export 'ui/review_page.dart';
export 'ui/devices_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Vortice Local Maintenance native dependencies',
    ], await rootBundle.loadString('assets/THIRD_PARTY_NOTICES.txt'));
  });
  try {
    await RustLib.init();
    final base = await getApplicationSupportDirectory();
    final override = Platform.isLinux
        ? Platform.environment['VORTICE_MAINTENANCE_DATA']
        : null;
    final store = await openLabWorkspace(
      Directory(override ?? '${base.path}/maintenance-local-v1'),
      office: Platform.isLinux,
    );
    if (Platform.isAndroid) {
      try {
        final lost = await ImagePicker().retrieveLostData();
        if (store.setting('pendingInspectionPhoto') != null &&
            store.setting('pendingInspectionPhoto') ==
                store.workspace?['jobId']) {
          if (lost.exception != null) throw lost.exception!;
          for (final file in lost.files ?? <XFile>[]) {
            await store.attach(await file.readAsBytes());
            store.setSetting('photoRecoveryError', null);
          }
        }
      } catch (_) {
        store.setSetting(
          'photoRecoveryError',
          'The interrupted photo could not be recovered. Your saved inspection is retained; choose or take the photo again.',
        );
      } finally {
        store.setSetting('pendingInspectionPhoto', null);
      }
    }
    runApp(LabApp(store: store));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Vortice Local Maintenance could not open its saved work. Your files have been retained.\n\n$e',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
