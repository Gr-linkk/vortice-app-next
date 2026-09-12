import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/engines/engine_form.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/engines/engine_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  for (final role in ['operator', 'mechanic', 'supervisor']) {
    testWidgets('$role direct engine screen respects management permission', (
      tester,
    ) async {
      final profile = Profile(
        id: 'actor',
        email: 'actor@example.invalid',
        fullName: 'Actor',
        role: UserRole.clientMechanic,
        membershipManaged: true,
        organizationRoles: [role],
      );
      final container = ProviderContainer(
        overrides: [
          profileProvider.overrideWith((ref) async => profile),
          enginesForAssetProvider('asset').overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      Widget app(Widget body) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: body,
        ),
      );
      await tester.pumpWidget(app(const EngineScreen(assetId: 'asset')));
      await tester.pumpAndSettle();
      expect(
        find.byType(FloatingActionButton),
        role == 'supervisor' ? findsOneWidget : findsNothing,
      );
      if (role != 'supervisor') {
        await tester.pumpWidget(
          app(const Scaffold(body: EngineForm(assetId: 'asset'))),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Asset management permission required.'),
          findsOneWidget,
        );
        expect(find.byType(TextFormField), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
