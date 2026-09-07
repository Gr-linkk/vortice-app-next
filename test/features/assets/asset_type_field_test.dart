import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/equipment_illustration.dart';
import 'package:vortice_app/features/assets/asset_type_field.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';

const _rib = AssetType(
  id: '00000000-0000-0000-0000-000000000011',
  name: 'RIB / Inflatable Boat',
);
const _telehandler = AssetType(
  id: '00000000-0000-0000-0000-00000000001c',
  name: 'Telehandler',
);
const _custom = AssetType(
  id: 'custom-owner-type',
  name: 'Special workshop rig',
);

void main() {
  testWidgets('requires a type and returns the stable selected ID', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Form(
            key: formKey,
            child: AssetTypeField(
              types: const [_rib, _telehandler, _custom],
              selectedId: null,
              onChanged: (id) => selected = id,
            ),
          ),
        ),
      ),
    );
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Telehandler').last);
    await tester.pumpAndSettle();
    expect(selected, _telehandler.id);
    expect(formKey.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'existing type remains readable in Spanish large text ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? changed;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: AssetTypeField(
                  types: const [_rib, _telehandler, _custom],
                  selectedId: _rib.id,
                  onChanged: (id) => changed = id,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lancha semirrígida / inflable'), findsOneWidget);
        expect(changed, isNull);
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .initialValue,
          _rib.id,
        );
        expect(find.byType(EquipmentIllustration), findsWidgets);
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        expect(find.text('Special workshop rig').last, findsOneWidget);
        await tester.tap(find.text('Manipulador telescópico').last);
        await tester.pumpAndSettle();
        expect(changed, _telehandler.id);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
