import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assurance/assurance_form.dart';
import 'package:vortice_app/features/assurance/assurance_repository.dart';
import 'package:vortice_app/features/assurance/assurance_screen.dart';
import '../maintenance/maintenance_screen_test.dart' as maintenance;
import '../fleet/fleet_test_support.dart';

class AssuranceFixture implements AssuranceRepository {
  bool fail = false, denied = false;
  final calls =
      <({String action, String operation, Map<String, dynamic> data})>[];
  Map<String, dynamic> catalog = {
    'asset': {
      'id': 'asset',
      'name': 'E2E-009 Harbour crane',
      'location': 'North dock',
    },
    'can_manage': true,
    'can_submit': true,
    'people': [
      {'id': 'mechanic', 'name': 'Alex Morgan'},
    ],
    'components': [],
    'transfers': [],
  };
  List<Map<String, dynamic>> items = [];
  @override
  Future<Map<String, dynamic>> context(String asset) async {
    if (denied) throw StateError('Denied');
    return catalog;
  }

  @override
  Future<List<Map<String, dynamic>>> inspections(String? asset) async => items;
  @override
  Future<void> write(
    String action,
    String target,
    int revision,
    String operation,
    Map<String, dynamic> data,
  ) async {
    calls.add((action: action, operation: operation, data: data));
    if (fail) {
      fail = false;
      throw TimeoutException('Lost reply');
    }
    if (action == 'transfer') {
      catalog = {
        ...catalog,
        'custody': {
          ...data,
          'revision': revision + 1,
          'responsible_name': 'Alex Morgan',
        },
      };
    }
    if (action == 'create') {
      items = [
        {...sampleInspection(), 'title': data['title']},
      ];
    }
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String type) async {}
  @override
  Future<void> discard(String path) async {}
  @override
  Future<String> imageUrl(String path) async =>
      throw StateError('test image offline');
}

Map<String, dynamic> sampleInspection() => {
  'id': 'inspection',
  'asset_id': 'asset',
  'asset_name': 'E2E-009 Harbour crane',
  'title': 'Annual lifting inspection',
  'site': 'North dock',
  'responsible_name': 'Alex Morgan',
  'can_manage': true,
  'can_submit': true,
  'revision': 0,
  'versions': [],
};
Future<void> pump(
  WidgetTester tester,
  Widget screen,
  AssuranceFixture fixture, {
  bool es = false,
  double width = 390,
  double scale = 1,
}) => maintenance.pumpMaintenance(
  tester,
  screen,
  maintenance.FixtureMaintenance(),
  es: es,
  width: width,
  scale: scale,
  overrides: [assuranceRepositoryProvider.overrideWithValue(fixture)],
);
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 25,
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  test(
    'expiry is inclusive; 30 day boundary and pending approval are independent',
    () {
      final today = DateTime(2026, 9, 6);
      Map<String, dynamic> item(String date) => {
        'approved': {'expires_on': date},
        'pending': {'expires_on': '2030-01-01'},
      };
      expect(inspectionState({}, today), 'unverified');
      expect(inspectionState(item('2026-09-05'), today), 'expired');
      expect(inspectionState(item('2026-09-06'), today), 'upcoming');
      expect(inspectionState(item('2026-10-06'), today), 'upcoming');
      expect(inspectionState(item('2026-10-07'), today), 'current');
      expect(inspectionDate('2026-02-30'), isNull);
      expect(inspectionDate('2026-2-3'), isNull);
      expect(inspectionDate('2028-02-29'), isNotNull);
    },
  );
  testWidgets(
    'transfer validates then retries identical operation and reopens saved location',
    (tester) async {
      final fixture = AssuranceFixture()..fail = true;
      await pump(tester, const AssuranceScreen(asset: 'asset'), fixture);
      await tapVisible(tester, find.text('Record transfer'));
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Record transfer'),
      );
      expect(fixture.calls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('site')),
        'E2E-009 Dry store',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex Morgan').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reason')),
        'Moving for inspection',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Record transfer'),
      );
      expect(find.textContaining('Could not confirm'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('site')))
            .enabled,
        false,
      );
      await tapVisible(tester, find.text('Retry save'));
      expect(fixture.calls.length, 2);
      expect(fixture.calls[0].operation, fixture.calls[1].operation);
      expect(fixture.calls[0].data, fixture.calls[1].data);
      expect(find.text('E2E-009 Dry store'), findsOneWidget);
      await tapVisible(tester, find.text('Record transfer'));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('site')))
            .controller!
            .text,
        'E2E-009 Dry store',
      );
    },
  );
  testWidgets(
    'register filters expiry separately from pending review and searches site',
    (tester) async {
      final fixture = AssuranceFixture()
        ..items = [
          {
            ...sampleInspection(),
            'approved': {'expires_on': '2000-01-01'},
            'pending': {'id': 'submission'},
          },
          {
            ...sampleInspection(),
            'id': 'second',
            'title': 'Engine certificate',
            'site': 'South dock',
            'approved': {'expires_on': '2199-01-01'},
          },
        ];
      await pump(tester, const AssuranceScreen(), fixture);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Expired'));
      expect(find.text('Annual lifting inspection'), findsOneWidget);
      expect(find.text('Engine certificate'), findsNothing);
      await tapVisible(
        tester,
        find.widgetWithText(ChoiceChip, 'Awaiting review'),
      );
      expect(find.text('Annual lifting inspection'), findsOneWidget);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(find.byType(TextField), 'South dock');
      await tester.pumpAndSettle();
      expect(find.text('Engine certificate'), findsOneWidget);
      expect(find.text('Annual lifting inspection'), findsNothing);
    },
  );
  testWidgets('read-only server context hides mutations', (tester) async {
    final fixture = AssuranceFixture();
    fixture.catalog = {
      ...fixture.catalog,
      'can_manage': false,
      'can_submit': false,
    };
    fixture.items = [
      {...sampleInspection(), 'can_manage': false, 'can_submit': false},
    ];
    await pump(tester, const AssuranceScreen(asset: 'asset'), fixture);
    expect(find.text('Record transfer'), findsNothing);
    expect(find.text('Add inspection'), findsNothing);
    expect(find.text('Submit renewal'), findsNothing);
  });
  for (final es in [false, true]) {
    testWidgets('custody and inspection render narrow large text $es', (
      tester,
    ) async {
      final fixture = AssuranceFixture()..items = [sampleInspection()];
      await pump(
        tester,
        const AssuranceScreen(asset: 'asset'),
        fixture,
        es: es,
        width: 320,
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'assurance-${es ? 'es' : 'en'}-320-large');
    });
    testWidgets('renewal form validates real dates and missing evidence $es', (
      tester,
    ) async {
      final fixture = AssuranceFixture();
      await pump(
        tester,
        AssuranceForm(
          action: 'submit',
          asset: 'asset',
          item: sampleInspection(),
        ),
        fixture,
        es: es,
        width: 320,
        scale: 1.5,
      );
      await tester.enterText(
        find.byKey(const ValueKey('inspected_on')),
        '2026-02-30',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expires_on')),
        '2026-01-01',
      );
      await tester.enterText(
        find.byKey(const ValueKey('procedure_notes')),
        'Procedure version 1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('result_notes')),
        'Pressure test passed',
      );
      await tapVisible(
        tester,
        find.widgetWithText(
          FilledButton,
          es ? 'Enviar renovación' : 'Submit renewal',
        ),
      );
      expect(fixture.calls, isEmpty);
      expect(
        find.text(es ? 'Revisa la fecha' : 'Check the date'),
        findsWidgets,
      );
      await tester.enterText(
        find.byKey(const ValueKey('inspected_on')),
        '2026-01-01',
      );
      await tapVisible(
        tester,
        find.widgetWithText(
          FilledButton,
          es ? 'Enviar renovación' : 'Submit renewal',
        ),
      );
      expect(fixture.calls, isEmpty);
      expect(
        find.textContaining(es ? 'JPEG o PNG' : 'JPEG or PNG'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'renewal-${es ? 'es' : 'en'}-320-large');
    });
  }
}
