import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/language_picker.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class _LanguageTestApp extends ConsumerWidget {
  const _LanguageTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: Column(
          children: [
            Text(languageName(locale)),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showLanguagePicker(context, ref),
                child: Text(AppLocalizations.of(context).language),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved Spanish can switch to French and persist the choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    SharedPreferences.setMockInitialValues({'app_locale': 'es'});
    await tester.pumpWidget(const ProviderScope(child: _LanguageTestApp()));
    await tester.pumpAndSettle();

    expect(find.text('Español'), findsOneWidget);
    expect(find.text('Idioma'), findsOneWidget);
    await tester.tap(find.text('Idioma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français').last);
    await tester.pumpAndSettle();

    expect(find.text('Français'), findsOneWidget);
    expect(find.text('Langue'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('app_locale'),
      'fr',
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('an unsupported saved language falls back to English', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_locale': 'de'});
    await tester.pumpWidget(const ProviderScope(child: _LanguageTestApp()));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
  });

  test('French translations preserve the work-order placeholder', () async {
    final french = await AppLocalizations.delegate.load(const Locale('fr'));

    expect(french.language, 'Langue');
    expect(french.workOrderDetail, 'Bon de travail');
    expect(french.greeting('Garrett'), 'Bonjour, Garrett');
  });
}
