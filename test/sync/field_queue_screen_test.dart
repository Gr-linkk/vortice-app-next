import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/sync/field_sync_status.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import '../features/fleet/fleet_test_support.dart';

void main() {
  setUpAll(loadFleetScreenshotFonts);
  for (final language in ['en', 'es']) {
    testWidgets('rejected field work is readable at 320px in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fieldWorkQueueProvider.overrideWithValue(null),
            fieldOperationsProvider.overrideWith(
              (_) => Stream.value([
                const FieldOperation(
                  id: 'operation-private-id',
                  subject: 'job-private-id',
                  kind: 'apply_maintenance_field_action',
                  status: 'failed',
                  error: 'PostgrestException 40001 job changed internal SQL',
                  payload: {
                    'p_action': 'save_report',
                    'p_data': {
                      'diagnosis': 'Worn pump seal',
                      'repair': 'Replaced and pressure tested',
                    },
                  },
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.darkNavyTheme.copyWith(
              textTheme: AppTheme.darkNavyTheme.textTheme.apply(
                fontFamily: 'Roboto',
              ),
              primaryTextTheme: AppTheme.darkNavyTheme.primaryTextTheme.apply(
                fontFamily: 'Roboto',
              ),
              appBarTheme: AppTheme.darkNavyTheme.appBarTheme.copyWith(
                titleTextStyle: AppTheme
                    .darkNavyTheme
                    .appBarTheme
                    .titleTextStyle
                    ?.copyWith(fontFamily: 'Roboto'),
              ),
              textButtonTheme: TextButtonThemeData(
                style: AppTheme.darkNavyTheme.textButtonTheme.style?.copyWith(
                  textStyle: WidgetStatePropertyAll(
                    AppTheme.darkNavyTheme.textButtonTheme.style?.textStyle
                        ?.resolve({})
                        ?.copyWith(fontFamily: 'Roboto'),
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: AppTheme.darkNavyTheme.outlinedButtonTheme.style
                    ?.copyWith(
                      textStyle: WidgetStatePropertyAll(
                        AppTheme
                            .darkNavyTheme
                            .outlinedButtonTheme
                            .style
                            ?.textStyle
                            ?.resolve({})
                            ?.copyWith(fontFamily: 'Roboto'),
                      ),
                    ),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const RepaintBoundary(
              key: Key('fleet-capture'),
              child: FieldQueueScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ExpansionTile));
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final details = find.byType(SelectableText);
      await tester.ensureVisible(details);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SelectableText>(details).data,
        contains('Worn pump seal'),
      );
      expect(find.textContaining('internal SQL'), findsNothing);
      expect(find.textContaining('job-private-id'), findsNothing);
      expect(find.textContaining('apply_maintenance'), findsNothing);
      expect(tester.takeException(), isNull);
      await captureFleet(tester, '011-sync-$language-320');
    });
  }
}
