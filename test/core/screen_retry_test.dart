import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/features/clients/client_screen.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/engines/engine_screen.dart';
import 'package:vortice_app/features/hours/hour_log_provider.dart';
import 'package:vortice_app/features/hours/hour_log_screen.dart';
import 'package:vortice_app/features/org_codes/org_code_provider.dart';
import 'package:vortice_app/features/org_codes/org_code_screen.dart';
import 'package:vortice_app/features/reminders/reminder_provider.dart';
import 'package:vortice_app/features/reminders/reminder_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

void main() {
  for (final language in ['en', 'es']) {
    for (final screen in [
      'clients',
      'engines',
      'hours',
      'codes',
      'reminders',
    ]) {
      testWidgets('$screen retries a failed load in $language', (tester) async {
        var calls = 0;
        Future<List<T>> load<T>() async {
          if (++calls == 1) throw TimeoutException('offline');
          return <T>[];
        }

        final (override, widget) = switch (screen) {
          'clients' => (
            clientsProvider.overrideWith((_) => load()),
            const ClientScreen(),
          ),
          'engines' => (
            enginesForAssetProvider('asset').overrideWith((_) => load()),
            const EngineScreen(assetId: 'asset'),
          ),
          'hours' => (
            hourLogsForEngineProvider('engine').overrideWith((_) => load()),
            const HourLogScreen(engineId: 'engine', assetId: 'asset'),
          ),
          'codes' => (
            orgCodesProvider.overrideWith((_) => load()),
            const OrgCodeScreen(),
          ),
          _ => (
            remindersProvider.overrideWith((_) => load()),
            const ReminderScreen(),
          ),
        };
        await tester.pumpWidget(
          ProviderScope(
            overrides: [override],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: widget,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(Scaffold).first);
        final retry = AppLocalizations.of(context).retry;
        expect(calls, 1);
        expect(find.text(retry), findsOneWidget);
        await tester.tap(find.text(retry));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.text(retry), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
