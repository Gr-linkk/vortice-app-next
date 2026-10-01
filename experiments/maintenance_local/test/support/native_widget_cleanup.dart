import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

/// A widget can enqueue a serial read in Flutter's fake zone. Starting cleanup
/// in runAsync alone cannot drain that zone; keep pumping while native I/O and
/// the queue finish, with a finite deadline and the original errors preserved.
Future<void> finishNativeWidgetCleanup(
  WidgetTester tester,
  Future<void> Function() close,
) => finishNativeWidgetAction(tester, close);

/// Drain native actions queued behind reads created by the widget's fake zone.
/// This preserves the operation's error and fails after a bounded wait.
Future<void> finishNativeWidgetAction(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var finished = false;
  final closing = action();
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
  expect(finished, isTrue, reason: 'Native fixture action must finish.');
  await closing;
}
