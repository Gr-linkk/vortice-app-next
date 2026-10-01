import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'manual_fault_intake_legacy_backup_runner.dart' as runner;

void main() {
  test(
    'Exact accepted98 backup create, inspect, restore and reopen preserve new opaque records',
    () async {
      final args =
          jsonDecode(Platform.environment['MANUAL_FAULT_LEGACY_ARGS']!) as List;
      await runner.main(args.cast<String>());
    },
  );
}
