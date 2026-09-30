import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/src/rust/api/documents.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File('rust/target/debug/librust_lib_sync_lab.so').absolute.path,
      ),
    );
  });
  test(
    'FFI rejects damaged saved bytes instead of inventing empty records',
    () async {
      await expectLater(
        documentValues(bytes: [1, 2, 3]),
        throwsA(isA<AnyhowException>()),
      );
    },
  );
  test(
    'FFI preserves unicode and unknown meter values through serialization',
    () async {
      final doc = await createDocument(
        actor: 'device-one',
        fieldsJson: '{"meter":null,"notes":"Révision ⚙"}',
      );
      expect(
        await documentValues(bytes: doc),
        '{"meter":[null],"notes":["Révision ⚙"]}',
      );
    },
  );
}
