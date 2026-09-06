import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_create_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_job_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_list_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_asset_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_report_screen.dart';
import 'package:vortice_app/features/maintenance/maintenance_setup_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';
import '../fleet/fleet_test_support.dart';

Map<String, dynamic> jobData({
  bool manager = true,
  bool enabled = true,
  String status = 'in_progress',
}) => {
  'id': 'job',
  'asset_id': 'asset',
  'asset_name': 'North Harbour — Generator 02',
  'title': '250-hour generator service',
  'description': 'Replace oil and filters. Check for leaks under load.',
  'status': status,
  'assigned_to': 'mechanic',
  'assignee_name': 'Alex Morgan',
  'due_date': '2026-09-10',
  'component_name': 'Auxiliary generator',
  'priority': 'high',
  'revision': 2,
  'can_manage': manager,
  'can_work': enabled,
  'service_interval_id': 'plan',
  'hourly_cost': 40,
  'report': {
    'diagnosis': 'Scheduled service',
    'repair': 'Replaced oil and tested under load',
    'notes': 'No leaks',
  },
  'hours_at_end': 1250,
  'labour': [
    {
      'id': 'session1',
      'actor_id': 'mechanic',
      'started_at': '2026-09-06T10:00:00Z',
      'stopped_at': '2026-09-06T11:00:00Z',
    },
    {
      'id': 'session2',
      'actor_id': 'mechanic',
      'started_at': '2026-09-06T12:00:00Z',
      'stopped_at': '2026-09-06T12:30:00Z',
    },
  ],
  'parts': [
    {'id': 'part', 'description': 'Oil filter', 'quantity': 1, 'unit_cost': 25},
  ],
  'checklist_snapshot': [
    {
      'id': 'item',
      'description_en': 'Check oil pressure at operating temperature',
      'description_es':
          'Verificar presión de aceite a temperatura de funcionamiento',
      'requires_photo': false,
    },
  ],
  'checklist_answers': {
    'item': {'result': 'pass'},
  },
  'evidence_paths': [],
  'events': [
    {
      'kind': 'created',
      'actor_name': 'Morgan',
      'created_at': '2026-09-06T09:00:00Z',
    },
  ],
};
final catalog = <String, dynamic>{
  'asset': {
    'id': 'asset',
    'name': 'North Harbour — Generator 02',
    'asset_type_id': 'type',
    'location': 'Engine room',
    'maintenance_revision': 0,
  },
  'can_manage': true,
  'can_plan': true,
  'can_execute': true,
  'components': [
    {
      'id': 'engine',
      'label': 'Auxiliary generator',
      'current_hours': 1250,
      'maintenance_revision': 0,
    },
  ],
  'plans': [
    {
      'id': 'plan',
      'asset_id': 'asset',
      'engine_id': 'engine',
      'component_name': 'Auxiliary generator',
      'interval_label': '250-hour service',
      'interval_hours': 250,
      'last_service_hours': 1000,
      'next_due_hours': 1250,
      'current_hours': 1250,
      'revision': 0,
      'is_active': true,
    },
  ],
  'templates': [
    {'id': 'template', 'name': 'Generator maintenance checklist'},
  ],
  'assignees': [
    {'id': 'mechanic', 'name': 'Alex Morgan'},
  ],
};

class FixtureMaintenance extends MaintenanceRepository {
  FixtureMaintenance({Map<String, dynamic>? job}) : job = job ?? jobData();
  Map<String, dynamic> job;
  bool failNext = false;
  final writes = <({String id, String action, Map<String, dynamic> data})>[];
  @override
  Future<List<MaintenanceJob>> jobs({String? jobId, String? assetId}) async => [
    MaintenanceJob(job),
  ];
  @override
  Future<Map<String, dynamic>> workspace() async => {
    'assets': [
      {'id': 'asset', 'name': 'North Harbour — Generator 02'},
    ],
    'asset_types': [
      {'id': 'type', 'name': 'Marine generator'},
    ],
    'clients': [
      {'id': 'company', 'name': 'North Harbour'},
    ],
  };
  @override
  Future<Map<String, dynamic>> assetContext(String id) async => catalog;
  void record(String id, String action, Map<String, dynamic> data) {
    writes.add((id: id, action: action, data: data));
    if (failNext) {
      failNext = false;
      throw TimeoutException('response lost');
    }
  }

  @override
  Future<String> create(String operationId, Map<String, dynamic> data) async {
    record(operationId, 'create', data);
    return 'job';
  }

  @override
  Future<void> change(
    String jobId,
    int revision,
    String operationId,
    String action,
    Map<String, dynamic> data,
  ) async {
    record(operationId, action, data);
  }

  @override
  Future<String> setup(
    String operationId,
    String kind,
    String id,
    int revision,
    Map<String, dynamic> data,
  ) async {
    record(operationId, kind, data);
    return id;
  }

  @override
  Future<void> uploadEvidence(
    String path,
    Uint8List bytes,
    String contentType,
  ) async {}
  @override
  Future<String> evidenceUrl(String path) async =>
      'https://example.invalid/photo.png';
}

Future<void> pumpMaintenance(
  WidgetTester tester,
  Widget screen,
  FixtureMaintenance repository, {
  bool es = false,
  double width = 390,
  double scale = 1,
  UserRole role = UserRole.clientAdmin,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => screen),
      GoRoute(
        path: '/maintenance/jobs/:id',
        builder: (_, __) => const Scaffold(body: Text('Job saved')),
      ),
      GoRoute(
        path: '/maintenance',
        builder: (_, __) => const MaintenanceListScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(null),
        fieldWorkQueueProvider.overrideWithValue(null),
        maintenanceRepositoryProvider.overrideWithValue(repository),
        profileProvider.overrideWith(
          (_) async => Profile(
            id: 'mechanic',
            email: 'fixture@example.invalid',
            fullName: 'Alex Morgan',
            role: role,
          ),
        ),
        ...overrides,
      ],
      child: RepaintBoundary(
        key: const Key('fleet-capture'),
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.darkNavyTheme.copyWith(
            textTheme: AppTheme.darkNavyTheme.textTheme.apply(
              fontFamily: 'Roboto',
            ),
            primaryTextTheme: AppTheme.darkNavyTheme.primaryTextTheme.apply(
              fontFamily: 'Roboto',
            ),
            appBarTheme: AppTheme.darkNavyTheme.appBarTheme.copyWith(
              titleTextStyle: AppTheme.darkNavyTheme.appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'Roboto'),
            ),
            chipTheme: AppTheme.darkNavyTheme.chipTheme.copyWith(
              labelStyle: AppTheme.darkNavyTheme.chipTheme.labelStyle?.copyWith(
                fontFamily: 'Roboto',
              ),
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
          ),
          debugShowCheckedModeBanner: false,
          locale: Locale(es ? 'es' : 'en'),
          supportedLocales: const [Locale('en'), Locale('es')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadFleetScreenshotFonts);
  test('internal costs include every stopped labour session and parts', () {
    final job = MaintenanceJob(jobData());
    expect(job.completedLabourHours, 1.5);
    expect(job.labourCost + job.partsCost, 85);
  });
  test('live labour timestamps retain the server completion cost rounding', () {
    final job = MaintenanceJob({
      ...jobData(),
      'hourly_cost': 45,
      'parts': [
        {'quantity': 1, 'unit_cost': 18.75},
      ],
      'labour': [
        {
          'started_at': '2026-09-06T04:48:19.792271+00:00',
          'stopped_at': '2026-09-06T04:49:20.665931+00:00',
        },
        {
          'started_at': '2026-09-06T05:03:56.744311+00:00',
          'stopped_at': '2026-09-06T05:12:40.270681+00:00',
        },
      ],
    });
    expect(job.labourCost + job.partsCost, closeTo(26.055000375, 0.000000001));
    expect((job.labourCost + job.partsCost).toStringAsFixed(2), '26.06');
  });
  testWidgets('reapproval explains that the service baseline is preserved', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      const MaintenanceJobScreen(jobId: 'job'),
      FixtureMaintenance(
        job: {
          ...jobData(status: 'pending_review'),
          'service_applied_at': '2026-09-06T05:17:17Z',
        },
      ),
    );
    await tester.ensureVisible(find.text('Approve & complete'));
    await tester.tap(find.text('Approve & complete'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Closes this reopened job. Its previously completed service and next service due stay unchanged.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Completes this job and updates only its linked service plan.'),
      findsNothing,
    );
  });
  test('retry payload is detached from editable checklist input', () {
    final answers = {
      'item': {'result': 'pass'},
    };
    final write = MaintenanceWrite({'answers': answers});
    answers['item']!['result'] = 'fail';
    expect((write.data['answers'] as Map)['item'], {'result': 'pass'});
  });
  testWidgets('create retry reuses exact job identity and input', (
    tester,
  ) async {
    final repository = FixtureMaintenance()..failNext = true;
    await pumpMaintenance(
      tester,
      const MaintenanceCreateScreen(assetId: 'asset'),
      repository,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Work to do'),
      'Repair pump seal',
    );
    await tester.scrollUntilVisible(
      find.text('Create job'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Create job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create job'));
    await tester.pumpAndSettle();
    expect(repository.writes.length, 1);
    await tester.scrollUntilVisible(
      find.text('Retry save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Retry save'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(repository.writes.length, 2);
    expect(repository.writes[0].id, repository.writes[1].id);
    expect(repository.writes[0].data, repository.writes[1].data);
    expect(find.text('Job saved'), findsOneWidget);
  });
  testWidgets('mechanic can submit saved report and retry uncertain response', (
    tester,
  ) async {
    final repository = FixtureMaintenance()..failNext = true;
    await pumpMaintenance(
      tester,
      MaintenanceReportScreen(job: MaintenanceJob(jobData(manager: false))),
      repository,
      role: UserRole.clientMechanic,
    );
    await tester.scrollUntilVisible(
      find.text('Submit for review'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Submit for review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit for review'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Retry the same save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Retry the same save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry the same save'));
    await tester.pumpAndSettle();
    expect(repository.writes.map((w) => w.action), ['submit', 'submit']);
    expect(repository.writes[0].id, repository.writes[1].id);
    expect(repository.writes[0].data['completion_hours'], '1250');
  });
  testWidgets(
    'disabled execution leaves history visible without write actions',
    (tester) async {
      await pumpMaintenance(
        tester,
        const MaintenanceJobScreen(jobId: 'job'),
        FixtureMaintenance(job: jobData(enabled: false)),
      );
      expect(find.text('Start labour'), findsNothing);
      expect(find.text('Report & submit'), findsNothing);
      expect(
        find.text('History is available; execution is disabled.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('unassigned mechanic cannot approve a submitted job in the UI', (
    tester,
  ) async {
    await pumpMaintenance(
      tester,
      const MaintenanceJobScreen(jobId: 'job'),
      FixtureMaintenance(
        job: jobData(manager: false, status: 'pending_review'),
      ),
      role: UserRole.clientMechanic,
    );
    expect(find.text('Approve & complete'), findsNothing);
    expect(find.text('Return'), findsNothing);
  });
  testWidgets(
    'removing a checklist photo clears selection without changing saved data',
    (tester) async {
      final data = jobData();
      (data['checklist_snapshot'] as List).first['requires_photo'] = true;
      (data['checklist_answers'] as Map)['item']['photo_path'] =
          'job/me/photo.jpg';
      data['evidence_paths'] = ['job/me/photo.jpg'];
      await pumpMaintenance(
        tester,
        MaintenanceReportScreen(job: MaintenanceJob(data)),
        FixtureMaintenance(),
      );
      await tester.scrollUntilVisible(
        find.byTooltip('Remove from report'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byTooltip('Remove from report'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from report'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        (data['checklist_answers'] as Map)['item']['photo_path'],
        'job/me/photo.jpg',
      );
      expect(find.byTooltip('Remove from report'), findsNothing);
    },
  );
  for (final name in [
    'work',
    'detail',
    'report',
    'asset',
    'create',
    'plan',
    'component',
  ]) {
    testWidgets('$name supports Spanish large text at 320px', (tester) async {
      final screen = switch (name) {
        'work' => const MaintenanceListScreen(),
        'detail' => const MaintenanceJobScreen(jobId: 'job'),
        'report' => MaintenanceReportScreen(job: MaintenanceJob(jobData())),
        'asset' => const MaintenanceAssetScreen(assetId: 'asset'),
        'create' => const MaintenanceCreateScreen(assetId: 'asset'),
        'plan' => MaintenanceSetupScreen(
          kind: 'plan',
          assetId: 'asset',
          catalog: catalog,
        ),
        _ => const MaintenanceSetupScreen(kind: 'component', assetId: 'asset'),
      };
      await pumpMaintenance(
        tester,
        screen,
        FixtureMaintenance(),
        es: true,
        width: 320,
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'maintenance-$name-es-large');
      for (var i = 0; i < 7; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -330));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await captureFleet(tester, 'maintenance-$name-es-large-bottom');
      await pumpMaintenance(tester, screen, FixtureMaintenance());
      expect(tester.takeException(), isNull);
      await captureFleet(tester, 'maintenance-$name-en');
    });
  }
}
