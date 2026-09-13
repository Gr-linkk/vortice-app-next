import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/assets/import/fleet_import_screen.dart';
import 'package:vortice_app/features/assets/import/fleet_import_repository.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/models/profile.dart';
import '../maintenance/maintenance_screen_test.dart'
    show pumpMaintenance, FixtureMaintenance;
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

class ImportFixture extends FleetImportRepository {
  Map<String, dynamic>? draft;
  int commits = 0, previews = 0;
  Object? failure;
  @override
  Future<Map<String, dynamic>?> pending() async => draft;
  @override
  Future<void> discard() async {
    draft = null;
  }

  @override
  Future<Map<String, dynamic>> context(String? client) async => {
    'client_id': 'fleet',
    'clients': [
      {'id': 'fleet', 'name': 'Our fleet'},
    ],
    'assets': [],
    'templates': [],
  };
  @override
  Future<Map<String, dynamic>> preview(
    String client,
    List<Map<String, dynamic>> assets,
  ) async {
    previews++;
    return {'errors': []};
  }

  @override
  Future<Map<String, dynamic>> commit(
    String client,
    List<Map<String, dynamic>> assets,
  ) async {
    commits++;
    draft = {'p_client': client, 'p_assets': assets, 'p_preview': false};
    if (failure != null) throw failure!;
    draft = null;
    return {'equipment_count': assets.length, 'assets': []};
  }
}

Future<void> visibleTap(WidgetTester tester, Finder f) async {
  final scroll = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(f, 250, scrollable: scroll);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  for (final es in [false, true]) {
    testWidgets('import preview, rejected save and retry at 320px 200% $es', (
      tester,
    ) async {
      final fixture = ImportFixture();
      await pumpMaintenance(
        tester,
        const FleetImportScreen(),
        FixtureMaintenance(),
        role: UserRole.owner,
        width: 320,
        scale: 2,
        es: es,
        overrides: [
          fleetImportRepositoryProvider.overrideWithValue(fixture),
          assetTypesProvider.overrideWith(
            (_) async => [const AssetType(id: 'type', name: 'Excavator')],
          ),
        ],
      );
      await captureFleet(tester, 'import-start-320-${es ? 'es' : 'en'}');
      await tester.enterText(
        find.byKey(const Key('import-paste')),
        'Name,Type,Serial\nMachine 12,Excavator,001234',
      );
      await visibleTap(
        tester,
        find.text(es ? 'Usar tabla pegada' : 'Use pasted table'),
      );
      await captureFleet(tester, 'import-mapping-320-${es ? 'es' : 'en'}');
      await visibleTap(
        tester,
        find.text(es ? 'Vista previa' : 'Preview import'),
      );
      expect(fixture.previews, 1);
      expect(fixture.commits, 0);
      await captureFleet(tester, 'import-preview-320-${es ? 'es' : 'en'}');
      fixture.failure = const PostgrestException(
        message: 'Fleet changed; review again',
        code: 'P0001',
      );
      await visibleTap(tester, find.byKey(const Key('import-confirm')));
      expect(fixture.draft, isNull);
      await visibleTap(
        tester,
        find.text(es ? 'Vista previa' : 'Preview import'),
      );
      fixture.failure = TimeoutException('Response lost');
      await visibleTap(tester, find.byKey(const Key('import-confirm')));
      expect(fixture.draft!['p_assets'][0]['serial_number'], '001234');
      fixture.failure = null;
      await visibleTap(
        tester,
        find.text(es ? 'Reintentar importación' : 'Retry same import'),
      );
      expect(fixture.commits, 3);
      expect(fixture.draft, isNull);
      expect(
        find.text(es ? 'Equipos importados' : 'Equipment imported'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
