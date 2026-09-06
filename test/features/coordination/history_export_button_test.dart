import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/coordination/asset_history_screen.dart';
import 'coordination_screen_test.dart' as fixture;

void main() {
  testWidgets(
    'export button hands a complete named CSV to the native share plugin',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'vortice-export-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        pathChannel,
        (_) async => directory.path,
      );
      Map<Object?, Object?>? shared;
      String? csv;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'share');
        shared = Map<Object?, Object?>.from(call.arguments as Map);
        csv = File(
          (shared!['paths'] as List).single as String,
        ).readAsStringSync();
        return '';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(pathChannel, null);
        messenger.setMockMethodCallHandler(shareChannel, null);
      });
      final repository = fixture.FixtureCoordination();
      await fixture.pumpCoordination(
        tester,
        const AssetHistoryScreen(assetId: 'asset'),
        repository,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Export filtered history'));
        for (var attempt = 0; attempt < 100 && shared == null; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(shared, isNotNull);
      expect(
        (shared!['paths'] as List).single,
        matches(r'Vortice-history-\d{4}-\d{2}-\d{2}\.csv$'),
      );
      expect(shared!['mimeTypes'], ['text/csv']);
      expect(csv, contains('Part removed'));
      expect(csv, contains('Part recorded'));
      expect(csv, contains('12.50 USD'));
      expect(repository.historyQueries.last.beforeId, 'event-2');
      expect(repository.historyQueries.last.asOf, '2026-09-06T09:00:00Z');
      expect(find.text('Preparing all pages…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
