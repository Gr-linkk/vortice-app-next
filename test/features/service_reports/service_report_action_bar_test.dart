import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/service_reports/service_report_action_bar.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

void main() {
  testWidgets('shows reachable signature and submit actions', (tester) async {
    var signaturePressed = false;
    var submitPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          bottomNavigationBar: ServiceReportActionBar(
            signatureSaved: false,
            isLoading: false,
            canSubmit: true,
            onOpenSignature: () => signaturePressed = true,
            onSubmit: () => submitPressed = true,
          ),
        ),
      ),
    );

    expect(find.text('Technician Signature'), findsOneWidget);
    expect(find.text('Submit Report'), findsOneWidget);

    await tester.tap(find.text('Technician Signature'));
    await tester.tap(find.text('Submit Report'));

    expect(signaturePressed, isTrue);
    expect(submitPressed, isTrue);
  });
}
