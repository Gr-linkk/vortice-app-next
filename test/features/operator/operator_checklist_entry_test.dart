import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/operator/operator_checklist_screen.dart';
import 'package:vortice_app/features/operator/operator_checklist_run_form.dart';
import 'package:vortice_app/features/operator/operator_checklist_draft_store.dart';
import 'package:vortice_app/features/operator/operator_checklist_support.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_template.dart';
import '../fleet/fleet_test_support.dart'
    show captureFleet, loadFleetScreenshotFonts;

const assets = <Map<String, dynamic>>[
  {'id': 'dredge', 'name': 'Ellicott 460SL', 'client_id': 'company'},
  {'id': 'truck', 'name': 'Service truck', 'client_id': 'company'},
];
const templates = [
  ChecklistTemplate(
    id: 'dredge-check',
    name: 'Dredge pre-operation',
    checklistType: 'operator_daily',
    scopeAssetId: 'dredge',
  ),
  ChecklistTemplate(
    id: 'truck-check',
    name: 'Truck pre-operation',
    checklistType: 'operator_daily',
    scopeAssetId: 'truck',
  ),
];
Map<String, dynamic> draft({String? assignment}) => {
  ...encodeOperatorChecklistDraft(
    asset: assets.first,
    template: templates.first,
    responses: {'oil': 'monitor'},
    notes: {'oil': 'Check again'},
    completedAt: DateTime(2026, 9, 12),
    currentHours: 120,
    generalNotes: 'Saved dredge',
    photos: {
      'oil': Uint8List.fromList([1, 2, 3]),
    },
  ),
  'operation_id': 'dredge-operation',
  'started_at': '2026-09-12T00:00:00Z',
  if (assignment != null) 'assignment_id': assignment,
};
Widget app({
  String account = 'operator',
  bool dark = false,
  double scale = 1,
  List<Map<String, dynamic>> fleet = assets,
  List<ChecklistTemplate> catalog = templates,
  Future<List<Map<String, dynamic>>>? delayedAssets,
  Future<List<Map<String, dynamic>>> Function()? loadAssets,
  Future<List<Map<String, dynamic>>> Function()? assignments,
  OperatorChecklistScreen screen = const OperatorChecklistScreen(),
}) => ProviderScope(
  overrides: [
    sessionProvider.overrideWithValue(
      Session(
        accessToken: 'fixture',
        tokenType: 'bearer',
        user: User(
          id: account,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-09-12T00:00:00Z',
        ),
      ),
    ),
    profileProvider.overrideWith((ref) async => null),
    operatorAssignedAssetsProvider.overrideWith(
      (ref) async => loadAssets != null
          ? await loadAssets()
          : delayedAssets == null
          ? fleet
          : await delayedAssets,
    ),
    checklistTemplatesProvider.overrideWith((ref) async => catalog),
    checklistItemsProvider.overrideWith((ref, id) async => []),
    myChecklistAssignmentsProvider.overrideWith(
      (ref) async => assignments == null ? [] : await assignments(),
    ),
  ],
  child: RepaintBoundary(
    key: const Key('fleet-capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    ),
  ),
);
Future<void> seed({String? assignment}) async {
  SharedPreferences.setMockInitialValues({
    accountStorageKey('operator', operatorChecklistDraftKey): jsonEncode(
      draft(assignment: assignment),
    ),
  });
}

void main() {
  setUpAll(loadFleetScreenshotFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'same asset drafts show the frozen checklist version and original start time',
    (tester) async {
      final store = OperatorChecklistDraftStore('operator', () => 'operator');
      final firstStart = DateTime(2026, 9, 12, 8, 15);
      final secondStart = DateTime(2026, 9, 12, 11, 30);
      await store.save({
        ...draft(),
        'started_at': firstStart.toIso8601String(),
      });
      await store.save({
        ...draft(),
        'operation_id': 'second-run',
        'templateId': 'dredge-check-v2',
        'started_at': secondStart.toIso8601String(),
        'generalNotes': 'Later run',
      });
      await tester.pumpWidget(
        app(
          catalog: [
            ...templates,
            templates.first.copyWith(
              id: 'dredge-check-v2',
              name: 'Dredge running checks',
              version: 2,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resume Ellicott 460SL checklist'), findsNWidgets(2));
      final firstSubtitle = find.textContaining('Dredge pre-operation · v1');
      final secondSubtitle = find.textContaining('Dredge running checks · v2');
      expect(firstSubtitle, findsOneWidget);
      expect(secondSubtitle, findsOneWidget);
      final localizations = MaterialLocalizations.of(
        tester.element(firstSubtitle),
      );
      expect(
        tester.widget<Text>(firstSubtitle).data,
        contains(
          localizations.formatTimeOfDay(TimeOfDay.fromDateTime(firstStart)),
        ),
      );
      expect(
        tester.widget<Text>(secondSubtitle).data,
        contains(
          localizations.formatTimeOfDay(TimeOfDay.fromDateTime(secondStart)),
        ),
      );
      await tester.tap(secondSubtitle);
      await tester.pumpAndSettle();
      final form = tester.widget<OperatorChecklistRunForm>(
        find.byType(OperatorChecklistRunForm),
      );
      expect(form.template.id, 'dredge-check-v2');
      expect(form.generalNotes, 'Later run');
    },
  );
  testWidgets(
    'generic entry offers saved asset explicitly and starting another preserves its fields photos and replay ID',
    (tester) async {
      await seed();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(OperatorChecklistRunForm), findsNothing);
      expect(find.text('Resume Ellicott 460SL checklist'), findsOneWidget);
      await tester.tap(find.text('Start another checklist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Service truck'));
      await tester.pumpAndSettle();
      expect(find.byType(OperatorChecklistRunForm), findsOneWidget);
      expect(find.text('Service truck'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Resume Service truck checklist'), findsOneWidget);
      await tester.tap(find.text('Resume Ellicott 460SL checklist'));
      await tester.pumpAndSettle();
      final form = tester.widget<OperatorChecklistRunForm>(
        find.byType(OperatorChecklistRunForm),
      );
      expect(form.generalNotes, 'Saved dredge');
      expect(form.responses, {'oil': 'monitor'});
      expect(form.photos['oil'], [1, 2, 3]);
      final saved = await OperatorChecklistDraftStore(
        'operator',
        () => 'operator',
      ).list();
      expect(
        saved.singleWhere((d) => d['assetId'] == 'dredge')['operation_id'],
        'dredge-operation',
      );
    },
  );
  testWidgets(
    'generic first run selects an asset even when the fleet contains only one',
    (tester) async {
      await tester.pumpWidget(app(fleet: [assets.first]));
      await tester.pumpAndSettle();
      expect(find.byType(OperatorChecklistRunForm), findsNothing);
      await tester.tap(find.text('Ellicott 460SL'));
      await tester.pumpAndSettle();
      expect(find.byType(OperatorChecklistRunForm), findsOneWidget);
    },
  );
  testWidgets(
    'multiple publications require a choice and inactive or wrong-asset templates never appear',
    (tester) async {
      await tester.pumpWidget(
        app(
          catalog: [
            ...templates,
            templates.last.copyWith(
              id: 'second',
              name: 'Second truck procedure',
            ),
            templates.last.copyWith(
              id: 'retired',
              name: 'Retired procedure',
              isActive: false,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Service truck'));
      await tester.pumpAndSettle();
      expect(find.byType(OperatorChecklistRunForm), findsNothing);
      expect(find.text('Second truck procedure'), findsOneWidget);
      expect(find.text('Retired procedure'), findsNothing);
      expect(find.text('Dredge pre-operation'), findsNothing);
      await tester.tap(find.text('Second truck procedure'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OperatorChecklistRunForm>(
              find.byType(OperatorChecklistRunForm),
            )
            .template
            .id,
        'second',
      );
    },
  );
  testWidgets(
    'explicit asset entry cannot silently resume another asset draft',
    (tester) async {
      await seed();
      await tester.pumpWidget(
        app(screen: const OperatorChecklistScreen(initialAssetId: 'truck')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OperatorChecklistRunForm>(
              find.byType(OperatorChecklistRunForm),
            )
            .assetName,
        'Service truck',
      );
      expect(
        (await OperatorChecklistDraftStore(
          'operator',
          () => 'operator',
        ).list()).length,
        2,
      );
    },
  );
  testWidgets('loading blocks entry until draft discovery completes', (
    tester,
  ) async {
    await seed();
    final loaded = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(app(delayedAssets: loaded.future));
    await tester.pump();
    expect(find.text('Service truck'), findsNothing);
    loaded.complete(assets);
    await tester.pumpAndSettle();
    expect(find.text('Resume Ellicott 460SL checklist'), findsOneWidget);
  });
  testWidgets(
    'another account and revoked assets cannot reopen stored draft data',
    (tester) async {
      await seed();
      await tester.pumpWidget(app(account: 'different'));
      await tester.pumpAndSettle();
      expect(find.text('Resume Ellicott 460SL checklist'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(fleet: [assets.last]));
      await tester.pumpAndSettle();
      expect(find.text('Resume Ellicott 460SL checklist'), findsNothing);
      expect(find.byType(OperatorChecklistRunForm), findsNothing);
    },
  );
  testWidgets(
    'pinned assignment resumes retired version and preserves assignment identity',
    (tester) async {
      await seed(assignment: 'assigned');
      await tester.pumpWidget(
        app(
          catalog: [templates.first.copyWith(isActive: false), templates.last],
          screen: const OperatorChecklistScreen(
            initialAssignmentId: 'assigned',
          ),
          assignments: () async => [
            {
              'id': 'assigned',
              'status': 'in_progress',
              'assets': {'id': 'dredge'},
              'checklist_templates': {'id': 'dredge-check'},
            },
          ],
        ),
      );
      await tester.pumpAndSettle();
      final form = tester.widget<OperatorChecklistRunForm>(
        find.byType(OperatorChecklistRunForm),
      );
      expect(form.template.id, 'dredge-check');
      expect(form.responses, {'oil': 'monitor'});
      expect(
        (await OperatorChecklistDraftStore(
          'operator',
          () => 'operator',
        ).list()).single['assignment_id'],
        'assigned',
      );
    },
  );
  testWidgets('assignment restoration waits for a concurrent fleet refresh', (
    tester,
  ) async {
    await seed(assignment: 'assigned');
    final assignment = Completer<List<Map<String, dynamic>>>();
    final refreshingFleet = Completer<List<Map<String, dynamic>>>();
    var reads = 0;
    await tester.pumpWidget(
      app(
        screen: const OperatorChecklistScreen(initialAssignmentId: 'assigned'),
        loadAssets: () async =>
            ++reads == 1 ? [] : await refreshingFleet.future,
        assignments: () => assignment.future,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OperatorChecklistScreen)),
    );
    container.invalidate(operatorAssignedAssetsProvider);
    await tester.pump();
    assignment.complete([
      {
        'id': 'assigned',
        'status': 'in_progress',
        'assets': {'id': 'dredge'},
        'checklist_templates': {'id': 'dredge-check'},
      },
    ]);
    await tester.pump();
    refreshingFleet.complete(assets);
    await tester.pumpAndSettle();
    expect(find.byType(OperatorChecklistRunForm), findsOneWidget);
    expect(find.textContaining('Your draft is kept'), findsNothing);
    expect(
      tester
          .widget<OperatorChecklistRunForm>(
            find.byType(OperatorChecklistRunForm),
          )
          .responses,
      {'oil': 'monitor'},
    );
  });
  testWidgets(
    'changed assignment cannot attach saved answers to a different asset',
    (tester) async {
      await seed(assignment: 'assigned');
      await tester.pumpWidget(
        app(
          screen: const OperatorChecklistScreen(
            initialAssignmentId: 'assigned',
          ),
          assignments: () async => [
            {
              'id': 'assigned',
              'status': 'pending',
              'assets': {'id': 'truck'},
              'checklist_templates': {'id': 'truck-check'},
            },
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OperatorChecklistRunForm), findsNothing);
      expect(find.textContaining('Your draft is kept'), findsOneWidget);
      expect(
        (await OperatorChecklistDraftStore(
          'operator',
          () => 'operator',
        ).list()).single['assetId'],
        'dredge',
      );
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'native ${dark ? 'dark' : 'light'} draft and searchable fleet layout at narrow large text',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await seed();
        final fleet = [
          ...assets,
          for (var i = 0; i < 12; i++)
            {
              'id': 'asset-$i',
              'name': 'Workshop equipment $i with a long descriptive name',
              'client_id': 'company',
            },
        ];
        await tester.pumpWidget(app(dark: dark, scale: 1.4, fleet: fleet));
        await tester.pumpAndSettle();
        await captureFleet(
          tester,
          'operator-drafts-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('Start another checklist'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'truck');
        await tester.pumpAndSettle();
        expect(find.text('Service truck'), findsOneWidget);
        expect(find.text('Ellicott 460SL'), findsNothing);
        await captureFleet(
          tester,
          'operator-assets-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('Service truck'));
        await tester.pumpAndSettle();
        await captureFleet(tester, 'operator-run-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
