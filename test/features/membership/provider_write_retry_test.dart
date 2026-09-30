import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/sync/field_evidence.dart';

import 'organization_work_execution_test.dart' as fixture;
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

class RejectedOnce extends fixture.ExecutionFixture {
  RejectedOnce(String code)
    : failure = PostgrestException(message: 'Write response', code: code);
  Object? failure;
  final revisions = <int>[];

  @override
  Future<void> changeOperation(
    String id,
    int revision,
    String operation,
    String action,
    Map<String, dynamic> values,
  ) async {
    revisions.add(revision);
    final error = failure;
    failure = null;
    if (error != null) {
      calls.add({
        'id': operation,
        'action': action,
        'data': jsonDecode(jsonEncode(values)),
      });
      throw error;
    }
    await super.changeOperation(id, revision, operation, action, values);
  }
}

Future<void> press(WidgetTester tester, String label) async {
  await fixture.reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 2.0]) {
    testWidgets('phone retry workflow renders at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = RejectedOnce('504');
      await tester.pumpWidget(fixture.app(data, scale: scale));
      await tester.pumpAndSettle();
      await press(tester, 'Pause my labour');
      // Capture the persistent recovery controls after the transient error toast.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await fixture.reveal(tester, find.text('Retry action'), delta: -250);
      await captureFleet(tester, 'provider-action-uncertain-$scale');
      await press(tester, 'Retry action');
      await press(tester, 'Continue service report');
      data.failure = const PostgrestException(
        message: 'Gateway timeout',
        code: '504',
      );
      await press(tester, 'Save to server');
      expect(data.calls, hasLength(3));
      expect(
        (jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                accountStorageKey('actor', 'provider_report:provider:work'),
              )!,
            )
            as Map)['pending'],
        isNotNull,
      );
      await captureFleet(tester, 'provider-report-after-save-$scale');
      await fixture.reveal(tester, find.text('Retry request'));
      await captureFleet(tester, 'provider-report-uncertain-$scale');
      await press(tester, 'Retry request');
      expect(data.calls[1], data.calls[0]);
      expect(data.calls[3], data.calls[2]);
      expect(tester.takeException(), isNull);
      await leave(tester);
    });
  }

  testWidgets('provider gateway retry survives account change and reopen', (
    tester,
  ) async {
    final data = RejectedOnce('504');
    final key = accountStorageKey('actor', 'provider_action:work');
    await tester.pumpWidget(fixture.app(data));
    await tester.pumpAndSettle();
    await press(tester, 'Pause my labour');
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(key);
    expect(pending, isNotNull);
    expect(data.calls, hasLength(1));
    await leave(tester);

    await tester.pumpWidget(fixture.app(data, actor: 'other-account'));
    await tester.pumpAndSettle();
    expect(find.text('Retry action'), findsNothing);
    expect(prefs.getString(key), pending);
    expect(data.calls, hasLength(1));
    await leave(tester);

    data.data['revision'] = 19;
    await tester.pumpWidget(fixture.app(data));
    await tester.pumpAndSettle();
    await press(tester, 'Retry action');
    expect(data.calls[1], data.calls[0]);
    expect(data.revisions, [3, 3]);
    expect(prefs.getString(key), isNull);
    await leave(tester);
  });

  testWidgets('provider confirmed rejection permits a fresh corrected action', (
    tester,
  ) async {
    final data = RejectedOnce('40001');
    await tester.pumpWidget(fixture.app(data));
    await tester.pumpAndSettle();
    await press(tester, 'Pause my labour');
    expect(
      (await SharedPreferences.getInstance()).getString(
        accountStorageKey('actor', 'provider_action:work'),
      ),
      isNull,
    );
    expect(find.text('Retry action'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    await press(tester, 'Pause my labour');
    expect(find.byType(SnackBar), findsNothing);
    expect(data.calls[1]['id'], isNot(data.calls[0]['id']));
    await leave(tester);
  });

  testWidgets(
    'report gateway retry preserves its exact draft after reopening',
    (tester) async {
      final data = RejectedOnce('504');
      final key = accountStorageKey('actor', 'provider_report:provider:work');
      await tester.pumpWidget(fixture.app(data));
      await tester.pumpAndSettle();
      await press(tester, 'Continue service report');
      await press(tester, 'Save to server');
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(key)!) as Map;
      expect(saved['pending'], isNotNull);
      expect((saved['pending'] as Map)['id'], data.calls.single['id']);
      await leave(tester);

      data.data['revision'] = 19;
      await tester.pumpWidget(fixture.app(data));
      await tester.pumpAndSettle();
      await press(tester, 'Continue service report');
      data.failure = FieldEvidencePendingException(rejected: false);
      await press(tester, 'Retry request');
      expect(
        (jsonDecode(prefs.getString(key)!) as Map)['pending'],
        saved['pending'],
        reason: 'A later preflight failure cannot disprove the first commit.',
      );
      await press(tester, 'Retry request');
      expect(data.calls[1], data.calls[0]);
      expect(data.calls[2], data.calls[0]);
      expect(data.revisions, [3, 3, 3]);
      expect(prefs.getString(key), isNull);
      await leave(tester);
    },
  );

  testWidgets(
    'report rejection keeps editable input without the failed command',
    (tester) async {
      final data = RejectedOnce('P0001');
      final key = accountStorageKey('actor', 'provider_report:provider:work');
      await tester.pumpWidget(fixture.app(data));
      await tester.pumpAndSettle();
      await press(tester, 'Continue service report');
      await press(tester, 'Save to server');
      final saved =
          jsonDecode((await SharedPreferences.getInstance()).getString(key)!)
              as Map;
      expect(saved['pending'], isNull);
      expect((saved['data'] as Map)['diagnosis'], 'Pressure seal failed');
      expect(find.text('Retry request'), findsNothing);
      await press(tester, 'Save to server');
      expect(data.calls[1]['id'], isNot(data.calls[0]['id']));
      expect(data.calls[1]['data'], data.calls[0]['data']);
      await leave(tester);
    },
  );
}
