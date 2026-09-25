import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/workspace_layout.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  testWidgets('one workspace adapts navigation and keeps authoring protected', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = -1;
    Future<void> show(Size size, {bool hide = false, double scale = 1}) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.light]),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: WorkspaceLayout(
              destinations: primaryDestinations(UserRole.clientAdmin),
              selectedIndex: 0,
              onSelect: (value) => selected = value,
              spanish: false,
              french: true,
              hideNavigation: hide,
              compactNavigation: const Text('compact navigation'),
              child: const Scaffold(body: Text('same work forms')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(const Size(1440, 900));
    expect(find.text('same work forms'), findsOneWidget);
    expect(find.text('compact navigation'), findsNothing);
    await tester.tap(find.text('Bons de travail'));
    expect(selected, 2);
    await show(const Size(1440, 900), hide: true);
    expect(find.byType(ListTile), findsNothing);
    await show(const Size(390, 844));
    expect(find.text('compact navigation'), findsOneWidget);
    await show(const Size(1000, 800), scale: 2);
    expect(find.text('compact navigation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
