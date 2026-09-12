import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/add_asset_screen.dart';
import 'package:vortice_app/features/assets/edit_asset_screen.dart';
import 'package:vortice_app/features/assets/asset_type_field.dart';
import 'package:vortice_app/features/assets/asset_type_provider.dart';
import 'package:vortice_app/features/assurance/assurance_repository.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/profile.dart';
import '../fleet/fleet_test_support.dart' show loadFleetScreenshotFonts;

const _rib = AssetType(
  id: '00000000-0000-0000-0000-000000000011',
  name: 'RIB / Inflatable Boat',
  category: 'Marine Vessels',
);
const _custom = AssetType(
  id: 'custom-owner-type',
  name: 'Special workshop rig',
);
const _client = Profile(
  id: 'client',
  email: 'test@example.invalid',
  fullName: 'Company owner',
  role: UserRole.owner,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final types =
      (jsonDecode(File('seed/asset-types.json').readAsStringSync()) as List)
          .map(
            (row) => AssetType.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
  setUpAll(() async {
    if (!const bool.fromEnvironment('SAVE_LAND_CATALOG_PROOFS')) return;
    await loadFleetScreenshotFonts();
  });

  testWidgets('required selection returns the stable ID; cancel preserves it', (
    tester,
  ) async {
    final key = GlobalKey<FormState>();
    String? selected;
    await tester.pumpWidget(
      _app(
        Form(
          key: key,
          child: AssetTypeField(
            types: [...types, _custom],
            selectedId: null,
            onChanged: (id) => selected = id,
          ),
        ),
      ),
    );
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('asset-type-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-type-search')),
      'track loader',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact Track Loader'));
    await tester.pumpAndSettle();
    expect(selected, '00000000-0000-0000-0000-000000000024');
    expect(key.currentState!.validate(), isTrue);
    await tester.tap(find.byKey(const ValueKey('asset-type-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-type-search')),
      'unmatched nonsense',
    );
    await tester.pump();
    expect(find.textContaining('No matching types'), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(selected, '00000000-0000-0000-0000-000000000024');
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom names and translated categories remain searchable', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _app(
        AssetTypeField(
          types: [...types, _custom],
          selectedId: _rib.id,
          onChanged: (id) => selected = id,
        ),
        spanish: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('asset-type-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('asset-type-search')),
      'agricultura',
    );
    await tester.pumpAndSettle();
    expect(find.text('Tractor agrícola'), findsOneWidget);
    expect(find.text('Cortacésped de giro cero'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('asset-type-search')),
      'workshop',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_custom.name));
    await tester.pumpAndSettle();
    expect(selected, _custom.id);
    expect(tester.takeException(), isNull);
  });

  for (final edit in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        '${edit ? 'Edit' : 'Add'} real form searches and selects at 320px 200% ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          final form = edit
              ? const EditAssetScreen(
                  asset: Asset(
                    id: 'asset',
                    clientId: 'client',
                    assetTypeId: '00000000-0000-0000-0000-000000000011',
                    name: 'Existing equipment',
                  ),
                )
              : const AddAssetScreen();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                profileProvider.overrideWith((ref) async => _client),
                clientsProvider.overrideWith((ref) async => [_client]),
                assetTypesProvider.overrideWith((ref) async => types),
                assuranceContextProvider(
                  'asset',
                ).overrideWith((ref) async => {}),
              ],
              child: _app(
                form,
                dark: dark,
                spanish: true,
                scale: 2,
                boundary: boundary,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final field = find.byKey(const ValueKey('asset-type-picker'));
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          if (edit) {
            expect(find.text('Lancha semirrígida / inflable'), findsOneWidget);
          }
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('asset-type-search')),
            'compact',
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            boundary,
            '${edit ? 'edit' : 'add'}-${dark ? 'dark' : 'light'}-search',
          );
          await tester.tap(find.text('Excavadora compacta / mini'));
          await tester.pumpAndSettle();
          final selectedField = tester.widget<AssetTypeField>(
            find.byType(AssetTypeField),
          );
          expect(
            selectedField.selectedId,
            '00000000-0000-0000-0000-000000000023',
          );
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            boundary,
            '${edit ? 'edit' : 'add'}-${dark ? 'dark' : 'light'}-selected',
          );
        },
      );
    }
  }
}

Widget _app(
  Widget body, {
  bool dark = false,
  bool spanish = false,
  double scale = 1,
  GlobalKey? boundary,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
  locale: Locale(spanish ? 'es' : 'en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: boundary, child: child!),
  ),
  home: body is Scaffold || body is AddAssetScreen || body is EditAssetScreen
      ? body
      : Scaffold(body: body),
);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('SAVE_LAND_CATALOG_PROOFS')) return;
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('outputs/land-catalog/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
}
