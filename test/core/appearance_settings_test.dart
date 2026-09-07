import 'package:vortice_app/core/app_filter_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/appearance_settings.dart';
import 'package:vortice_app/core/theme.dart';
import '../features/fleet/fleet_test_support.dart';

class _AppearanceApp extends ConsumerWidget {
  const _AppearanceApp({this.spanish = false});
  final bool spanish;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: ref.watch(themeModeProvider),
    locale: Locale(spanish ? 'es' : 'en'),
    supportedLocales: const [Locale('en'), Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: const AppearanceSettingsScreen(),
  );
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  test(
    'unknown values use System; saved mode survives controller recreation',
    () async {
      SharedPreferences.setMockInitialValues({
        ThemeModeController.preferenceKey: 'invalid',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeModeController(prefs);
      addTearDown(controller.dispose);
      expect(controller.state, ThemeMode.system);
      await Future.wait([
        controller.select(ThemeMode.light),
        controller.select(ThemeMode.dark),
      ]);
      final restored = ThemeModeController(prefs);
      addTearDown(restored.dispose);
      expect(restored.state, ThemeMode.dark);
      expect(prefs.getString(ThemeModeController.preferenceKey), 'dark');
    },
  );

  test('failed persistence keeps the previous appearance', () async {
    final controller = ThemeModeController(null);
    addTearDown(controller.dispose);
    await expectLater(controller.select(ThemeMode.dark), throwsStateError);
    expect(controller.state, ThemeMode.system);
  });

  for (final dark in [false, true]) {
    testWidgets('ChoiceChip and FilterChip resolve contrasting text ($dark)', (tester) async {
      final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
      final palette = dark ? AppPalette.dark : AppPalette.light;
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: Wrap(children: [
        ChoiceChip(label: const Text('choice selected'), selected: true, onSelected: (_) {}),
        ChoiceChip(label: const Text('choice idle'), selected: false, onSelected: (_) {}),
        AppFilterChip(label: const Text('filter selected'), selected: true, onSelected: (_) {}),
        AppFilterChip(label: const Text('filter idle'), selected: false, onSelected: (_) {}),
      ]))));
      for (final type in ['choice', 'filter']) {
        final selected = tester.renderObject<RenderParagraph>(find.text('$type selected'));
        final idle = tester.renderObject<RenderParagraph>(find.text('$type idle'));
        expect(selected.text.style?.color, palette.onPrimary);
        expect(idle.text.style?.color, palette.textPrimary);
      }
    });
  }

  for (final spanish in [false, true]) {
    testWidgets(
      'settings saves and follows platform brightness at 320px (${spanish ? "es" : "en"})',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          ThemeModeController.preferenceKey: 'dark',
        });
        final prefs = await SharedPreferences.getInstance();
        tester.view.physicalSize = const Size(320, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appearancePreferencesProvider.overrideWithValue(prefs)],
            child: RepaintBoundary(
              key: const Key('fleet-capture'),
              child: _AppearanceApp(spanish: spanish),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Brightness brightness() => Theme.of(
          tester.element(find.byType(AppearanceSettingsScreen)),
        ).brightness;
        expect(brightness(), Brightness.dark);
        await captureFleet(tester, 'settings-${spanish ? "es" : "en"}-dark');
        await tester.tap(find.text(spanish ? 'Claro' : 'Light'));
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.light);
        expect(prefs.getString(ThemeModeController.preferenceKey), 'light');
        await captureFleet(tester, 'settings-${spanish ? "es" : "en"}-light');
        await tester.tap(find.text(spanish ? 'Sistema' : 'System'));
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.light);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.dark);
        expect(prefs.getString(ThemeModeController.preferenceKey), 'system');
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('both themes have readable primary, muted, action and input colors', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final palette in [AppPalette.light, AppPalette.dark]) {
      for (final surface in [
        palette.background,
        palette.surface,
        palette.surfaceVariant,
      ]) {
        expect(
          contrast(palette.textPrimary, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(palette.textSecondary, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(
        contrast(palette.onPrimary, palette.primary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
