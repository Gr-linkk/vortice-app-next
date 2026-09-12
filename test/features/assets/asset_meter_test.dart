import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/assets/asset_meter_card.dart';
import 'package:vortice_app/models/asset.dart';

class FakeMeterRepository implements AssetMeterRepository {
  (String, String, double)? recorded;
  @override
  Future<void> configure(String asset, String unit, double reading) async {
    recorded = (asset, unit, reading);
  }
}

void main() {
  const truck = Asset(
    id: 'truck',
    clientId: 'company',
    assetTypeId: 'truck-type',
    name: 'Truck 1',
    meterUnit: 'km',
  );
  testWidgets('truck reading submits original kilometres without conversion', (
    tester,
  ) async {
    final repository = FakeMeterRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [assetMeterRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AssetMeterSetupScreen(asset: truck)),
      ),
    );
    expect(find.text('Current reading (km)'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '62000');
    await tester.tap(find.text('Save reading'));
    await tester.pumpAndSettle();
    expect(repository.recorded, ('truck', 'km', 62000));
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing and nonfinite readings are not recorded at large text', (
    tester,
  ) async {
    final repository = FakeMeterRepository();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [assetMeterRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const AssetMeterSetupScreen(asset: truck),
        ),
      ),
    );
    for (final input in ['', 'NaN', '-1']) {
      await tester.enterText(find.byType(TextFormField), input);
      await tester.ensureVisible(find.text('Save reading'));
      await tester.tap(find.text('Save reading'));
      await tester.pump();
      expect(repository.recorded, isNull);
      expect(find.text('Enter a valid reading'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
