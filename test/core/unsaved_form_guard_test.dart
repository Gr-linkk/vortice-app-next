import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/unsaved_form_guard.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

Widget _guardApp({double textScale = 1}) => MaterialApp(
  locale: const Locale('fr'),
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
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: const _GuardPage(),
);

class _GuardPage extends StatefulWidget {
  const _GuardPage();
  @override
  State<_GuardPage> createState() => _GuardPageState();
}

class _GuardPageState extends State<_GuardPage> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: UnsavedFormGuard(
      fallbackRoute: '/home',
      controllers: [controller],
      isDirty: () => controller.text.isNotEmpty,
      child: TextField(controller: controller),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in [1.0, 2.0]) {
    testWidgets('French discard prompt stays usable at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(_guardApp(textScale: scale));
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      expect(find.text('Continuer à modifier'), findsOneWidget);
      expect(find.text('Abandonner'), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}
