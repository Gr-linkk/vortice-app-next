import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// A widget can enqueue a serial read in Flutter's fake zone. Starting cleanup
/// in runAsync alone cannot drain that zone; keep pumping while native I/O and
/// the queue finish, with a finite deadline and the original errors preserved.
Future<void> finishNativeWidgetCleanup(
  WidgetTester tester,
  Future<void> Function() close,
) async {
  var finished = false;
  final closing = close();
  unawaited(
    closing.then<void>(
      (_) => finished = true,
      onError: (Object error, StackTrace stack) => finished = true,
    ),
  );
  for (var attempt = 0; attempt < 100 && !finished; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finished, isTrue, reason: 'Native fixture cleanup must finish.');
  await closing;
}
