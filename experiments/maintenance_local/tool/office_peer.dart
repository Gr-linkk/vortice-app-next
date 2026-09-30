// An independent Dart peer for exercising the rendered Linux owner UI.
// Run only against a fresh acceptance-office fixture root; never ordinary data.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw StateError('Usage: office_peer.dart ACCEPTANCE_ROOT PHOTO_FIXTURE');
  }
  final root = Directory(args[0]);
  await RustLib.init(
    externalLibrary: ExternalLibrary.open(
      File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
    ),
  );
  final phone = await LabStore.open(
    Directory('${root.path}/peer-phone'),
    office: false,
  );
  final sync = PhoneSync(phone);
  await sync.enroll(await File('${root.path}/invitation.json').readAsString());
  while (phone.workspace == null) {
    await sync.sync();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await phone.update({
    'fluid': 'pass',
    'guards': 'attention',
    'meter': 314.25,
    'notes': 'Synthetic peer: inspect guard.',
  });
  await phone.attach(await File(args[1]).readAsBytes());
  await phone.submit();
  while (phone.receipts.isEmpty) {
    await sync.sync();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await File('${root.path}/revoke-now').writeAsString('yes', flush: true);
  while (!await File('${root.path}/replacement-invitation.json').exists()) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final c = PinnedConnection(sync.pairing!);
  try {
    await c.request('/bundle', {});
    throw StateError('Revocation failed.');
  } on StateError catch (e) {
    if (e.toString().contains('Revocation failed')) rethrow;
  } finally {
    c.close();
  }
  final replacement = await LabStore.open(
    Directory('${root.path}/peer-replacement'),
    office: false,
  );
  final restore = PhoneSync(replacement);
  await restore.enroll(
    await File('${root.path}/replacement-invitation.json').readAsString(),
    label: 'Replacement peer',
  );
  while (replacement.workspace == null) {
    await restore.sync();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (canonical(replacement.receipts) != canonical(phone.receipts) ||
      canonical(await replacement.evidence.manifest()) !=
          canonical(await phone.evidence.manifest())) {
    throw StateError('Restore mismatch');
  }
  await File('${root.path}/peer-result.json').writeAsString(
    jsonEncode({
      'passed': true,
      'transport': 'localhost',
      'submissions': replacement.submissions,
      'receipts': replacement.receipts,
      'blobs': await replacement.evidence.manifest(),
    }),
    flush: true,
  );
  await File('${root.path}/finish').writeAsString('yes', flush: true);
  await phone.close();
  await replacement.close();
}
