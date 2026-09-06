import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/coordination/asset_history_screen.dart';
import 'package:vortice_app/features/coordination/coordination_labels.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart';
import 'package:vortice_app/features/coordination/discussion_screen.dart';
import 'package:vortice_app/features/coordination/discussion_write_screen.dart';
import 'package:vortice_app/features/coordination/fleet_overview_screen.dart';
import 'package:vortice_app/features/notifications/notification_provider.dart';
import 'package:vortice_app/features/notifications/notifications_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';
import '../fleet/fleet_test_support.dart';

final fixturePost = <String, dynamic>{
  'id': 'post-1',
  'kind': 'handover',
  'author_id': 'mechanic',
  'author_name': 'Jordan Lee',
  'created_at': '2026-09-06T08:30:00Z',
  'team': 'company',
  'visibility': 'team',
  'body': 'Pump seal removed. Machine is isolated at the local disconnect.',
  'isolation': 'isolated',
  'next_steps':
      'Fit seal kit SK-42, pressure test and record the result before returning to service.',
  'mentions': [
    {'id': 'manager', 'name': 'Alex Morgan'},
  ],
  'attachments': <dynamic>[],
  'acknowledgements': <dynamic>[],
};
late Uint8List fixturePhoto;

class FixtureCoordination implements CoordinationRepository {
  Object? readError, postError, uploadError;
  bool canPost = true;
  final historyQueries = <HistoryQuery>[];
  final attentionQueries = <AttentionQuery>[];
  final threadQueries = <ThreadQuery>[];
  final writes = <({String id, Map<String, dynamic> data})>[];
  final uploads = <String>[];
  final acknowledgements = <String>[];
  final reads = <String?>[];
  final _rows = <Map<String, dynamic>>[
    {
      'id': 'fault-1',
      'kind': 'fault',
      'category': 'urgent_faults',
      'asset_id': 'asset',
      'asset_name': 'North Harbour — Generator 02',
      'title': 'Oil leaking from main pump seal',
      'managed': false,
      'reason': 'open',
    },
    {
      'id': 'job',
      'kind': 'job',
      'category': 'waiting_parts',
      'asset_id': 'asset',
      'asset_name': 'North Harbour — Generator 02',
      'title': 'Replace main pump seal',
      'reason': 'Seal kit SK-42 arrives tomorrow morning',
      'managed': true,
      'due_date': '2026-09-07',
    },
    {
      'id': 'plan',
      'kind': 'plan',
      'category': 'approaching_service',
      'asset_id': 'asset',
      'asset_name': 'North Harbour — Generator 02',
      'title': '250-hour service',
      'reason': '',
      'managed': false,
      'remaining_hours': 35,
    },
  ];
  @override
  Future<Map<String, dynamic>> attention(AttentionQuery query) async {
    attentionQueries.add(query);
    if (readError != null) throw readError!;
    final selected = _rows
        .where(
          (row) => query.category == null || row['category'] == query.category,
        )
        .toList();
    return {
      'generated_at': '2026-09-06T09:00:00Z',
      'items': selected,
      'has_more': false,
      'total': selected.length,
      'counts': {
        for (final key in attentionCategories.keys)
          key: _rows.where((r) => r['category'] == key).length,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> history(HistoryQuery query) async {
    historyQueries.add(query);
    if (readError != null) throw readError!;
    return {
      'asset_id': 'asset',
      'asset_name': 'North Harbour — Generator 02',
      'as_of': '2026-09-06T09:00:00Z',
      'has_more': query.before == null && query.search.isEmpty,
      'entries': query.search == 'missing'
          ? <dynamic>[]
          : [
              {
                'id': query.before == null ? 'event-2' : 'event-1',
                'asset_id': 'asset',
                'source_id': 'part',
                'source_type': 'parts',
                'job_id': 'job',
                'category': 'parts',
                'kind': query.before == null ? 'part_removed' : 'part_recorded',
                'occurred_at': query.before == null
                    ? '2026-09-06T08:30:00Z'
                    : '2026-09-06T07:30:00Z',
                'title': 'Pump seal SK-42',
                'body': 'Removed the worn seal before fitting the new kit.',
                'actor_name': 'Jordan Lee',
                'managed': true,
                'detail': {
                  'part_number': 'SK-42',
                  'quantity': 2,
                  'unit_cost': 12.5,
                  'total_cost': 25,
                },
              },
            ],
    };
  }

  @override
  Future<Map<String, dynamic>> thread(ThreadQuery query) async {
    threadQueries.add(query);
    if (readError != null) throw readError!;
    return {
      'id': 'job',
      'asset_id': 'asset',
      'asset_name': 'North Harbour — Generator 02',
      'title': 'Repair cooling leak',
      'can_post': canPost,
      'team': 'company',
      'managed': true,
      'has_more': false,
      'posts': [
        {
          ...fixturePost,
          'acknowledgements': [
            for (final id in acknowledgements)
              {
                'user_id': 'manager',
                'name': 'Alex Morgan',
                'created_at': '2026-09-06T09:00:00Z',
                'post_id': id,
              },
          ],
        },
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> people(PeopleQuery query) async => [
    {
      'id': 'recipient',
      'name': 'María Rodríguez — Maintenance supervisor',
      'role': 'client_admin',
    },
  ];
  @override
  Future<void> post(
    Subject subject,
    String operation,
    Map<String, dynamic> data,
  ) async {
    writes.add((id: operation, data: data));
    final error = postError;
    postError = null;
    if (error != null) throw error;
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    uploads.add(path);
    final error = uploadError;
    uploadError = null;
    if (error != null) throw error;
  }

  @override
  Future<String> photoUrl(String path) async => 'https://example.invalid/photo';
  @override
  Future<void> acknowledge(String post) async {
    acknowledgements.add(post);
  }

  @override
  Future<List<Map<String, dynamic>>> inbox() async => [];
  @override
  Future<void> markRead([String? post]) async {
    reads.add(post);
  }
}

class FixtureNotificationController extends NotificationController {
  final calls = <({String id, bool discussion})>[];
  @override
  Future<void> markRead(
    String notificationId, {
    bool discussion = false,
  }) async {
    calls.add((id: notificationId, discussion: discussion));
  }
}

Future<void> pumpCoordination(
  WidgetTester tester,
  Widget screen,
  FixtureCoordination repository, {
  double width = 390,
  double scale = 1,
  bool es = false,
  bool composer = false,
  List<Override> extraOverrides = const [],
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => composer
            ? Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => screen),
                    ),
                    child: const Text('Compose'),
                  ),
                ),
              )
            : screen,
      ),
      for (final path in [
        '/history/assets/:id',
        '/discussion/:kind/:id',
        '/maintenance/jobs/:id',
        '/fleet/faults/:id',
        '/maintenance/assets/:id',
        '/fleet/assets/:id',
      ])
        GoRoute(
          path: path,
          builder: (_, state) =>
              Scaffold(appBar: AppBar(), body: Text('Opened ${state.uri}')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coordinationRepositoryProvider.overrideWithValue(repository),
        profileProvider.overrideWith(
          (_) async => const Profile(
            id: 'manager',
            email: 'fixture@example.invalid',
            fullName: 'Alex Morgan',
            role: UserRole.clientAdmin,
          ),
        ),
        notificationsProvider.overrideWith((_) async => []),
        discussionPhotoPickerProvider.overrideWithValue(
          (_) async => XFile.fromData(
            fixturePhoto,
            name: 'seal.png',
            mimeType: 'image/png',
          ),
        ),
        ...extraOverrides,
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
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(bottom: 24),
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (composer) {
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
  }
}

Future<void> reach(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    350,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 30,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadFleetScreenshotFonts();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 32, 32),
      Paint()..color = Colors.blueGrey,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 32);
    fixturePhoto = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  testWidgets('history filters, details, pagination and job destination', (
    tester,
  ) async {
    final repository = FixtureCoordination();
    await pumpCoordination(
      tester,
      const AssetHistoryScreen(assetId: 'asset'),
      repository,
    );
    await tester.tap(find.text('Part removed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SK-42'), findsWidgets);
    await captureFleet(tester, 'coordination-history-en');
    await reach(tester, find.text('Older'));
    await tester.tap(find.text('Older'));
    await tester.pumpAndSettle();
    expect(repository.historyQueries.last.beforeId, 'event-2');
    expect(repository.historyQueries.last.asOf, '2026-09-06T09:00:00Z');
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repository.historyQueries.last.before, isNull);
    expect(repository.historyQueries.last.search, 'missing');
    expect(find.text('No events'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('handover retries same payload and does not reupload photos', (
    tester,
  ) async {
    final repository = FixtureCoordination()
      ..postError = TimeoutException('Lost response');
    await pumpCoordination(
      tester,
      const DiscussionWriteScreen(
        subject: (kind: 'job', id: 'job'),
        title: 'Repair cooling leak',
        providerTeam: false,
      ),
      repository,
      composer: true,
    );
    await tester.tap(find.text('Comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shift handover').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'What happened / current situation'),
      'Pump isolated. Seal removed.',
    );
    await reach(
      tester,
      find.widgetWithText(TextFormField, 'Next shift / outstanding work'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Next shift / outstanding work'),
      'Install seal kit and pressure test.',
    );
    await reach(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await reach(tester, find.text('Gallery'));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await reach(tester, find.text('Post note'));
    await tester.tap(find.text('Post note'));
    await tester.pumpAndSettle();
    expect(repository.writes, hasLength(1));
    expect(repository.writes.single.data['kind'], 'handover');
    expect(repository.writes.single.data['mentions'], ['recipient']);
    expect(repository.uploads, hasLength(1));
    await reach(tester, find.text('Retry sending'));
    expect(find.text('Retry sending'), findsOneWidget);
    await captureFleet(tester, 'coordination-handover-retry-en');
    await reach(tester, find.text('Retry sending'));
    await tester.tap(find.text('Retry sending'));
    await tester.pumpAndSettle();
    expect(repository.writes, hasLength(2));
    expect(repository.writes.last.id, repository.writes.first.id);
    expect(repository.writes.last.data, repository.writes.first.data);
    expect(repository.uploads, hasLength(1));
    expect(find.text('Compose'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('mentioned handover is focused and can be acknowledged', (
    tester,
  ) async {
    final repository = FixtureCoordination();
    await pumpCoordination(
      tester,
      const DiscussionScreen(
        kind: 'job',
        subjectId: 'job',
        focusPost: 'post-1',
      ),
      repository,
    );
    expect(repository.threadQueries.single.focus, 'post-1');
    await reach(tester, find.text('Acknowledge handover'));
    await captureFleet(tester, 'coordination-thread-en');
    await tester.tap(find.text('Acknowledge handover'));
    await tester.pumpAndSettle();
    expect(repository.acknowledgements, ['post-1']);
    expect(find.textContaining('Acknowledged by'), findsOneWidget);
    expect(find.text('Acknowledge handover'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'read-only discussion offers neither posting nor acknowledgment',
    (tester) async {
      final repository = FixtureCoordination()..canPost = false;
      await pumpCoordination(
        tester,
        const DiscussionScreen(kind: 'job', subjectId: 'job'),
        repository,
      );
      expect(find.text('Write a note or handover'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.text('Acknowledge handover'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'fleet indicator requests exact category and opens underlying job',
    (tester) async {
      final repository = FixtureCoordination();
      await pumpCoordination(tester, const FleetOverviewScreen(), repository);
      await captureFleet(tester, 'coordination-overview-en');
      await reach(tester, find.text('Waiting for parts').first);
      await tester.tap(find.text('Waiting for parts').first);
      await tester.pumpAndSettle();
      expect(repository.attentionQueries.last.category, 'waiting_parts');
      await reach(tester, find.textContaining('Replace main pump seal'));
      await tester.tap(find.textContaining('Replace main pump seal'));
      await tester.pumpAndSettle();
      expect(find.text('Opened /maintenance/jobs/job'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final entry in <String, Widget>{
    'history': const AssetHistoryScreen(assetId: 'asset'),
    'thread': const DiscussionScreen(kind: 'job', subjectId: 'job'),
    'overview': const FleetOverviewScreen(),
    'composer': const DiscussionWriteScreen(
      subject: (kind: 'job', id: 'job'),
      title: 'Reparar fuga del sistema de refrigeración',
      providerTeam: false,
    ),
  }.entries) {
    testWidgets(
      '${entry.key} Spanish enlarged layout and bottom action stay usable',
      (tester) async {
        await pumpCoordination(
          tester,
          entry.value,
          FixtureCoordination(),
          width: 320,
          scale: 1.5,
          es: true,
        );
        await captureFleet(tester, 'coordination-${entry.key}-es-large');
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
        await tester.pumpAndSettle();
        await captureFleet(tester, 'coordination-${entry.key}-es-large-bottom');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('history read failure offers retry and recovers', (tester) async {
    final repository = FixtureCoordination()
      ..readError = TimeoutException('Offline');
    await pumpCoordination(
      tester,
      const AssetHistoryScreen(assetId: 'asset'),
      repository,
    );
    expect(find.text('Retry'), findsOneWidget);
    repository.readError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Part removed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'inbox mention marks only the discussion inbox and opens its exact note',
    (tester) async {
      final controller = FixtureNotificationController();
      await pumpCoordination(
        tester,
        const NotificationsScreen(),
        FixtureCoordination(),
        extraOverrides: [
          notificationsProvider.overrideWith(
            (_) async => [
              AppNotification(
                id: 'post-1',
                userId: 'manager',
                title: 'Jordan Lee',
                body: 'Please review this handover',
                type: 'discussion_job',
                referenceId: 'job',
                read: false,
                createdAt: DateTime.utc(2026, 9, 6),
              ),
            ],
          ),
          notificationControllerProvider.overrideWith(() => controller),
        ],
      );
      await tester.tap(find.text('Please review this handover'));
      await tester.pumpAndSettle();
      expect(controller.calls, [(id: 'post-1', discussion: true)]);
      expect(
        find.text('Opened /discussion/job/job?post=post-1'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'enlarged Spanish handover menu and keyboard leave usable fields and action',
    (tester) async {
      await pumpCoordination(
        tester,
        const DiscussionWriteScreen(
          subject: (kind: 'job', id: 'job'),
          title: 'Reparar fuga de refrigeración',
          providerTeam: false,
        ),
        FixtureCoordination(),
        es: true,
        width: 320,
        scale: 1.5,
      );
      await tester.tap(find.text('Comentario'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relevo de turno').last);
      await tester.pumpAndSettle();
      await reach(tester, find.text('Sin confirmar'));
      await tester.tap(find.text('Sin confirmar'));
      await tester.pumpAndSettle();
      await captureFleet(tester, 'coordination-isolation-menu-es-large');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('No requiere aislamiento').last);
      await tester.pumpAndSettle();
      await reach(
        tester,
        find.widgetWithText(TextFormField, 'Próximo turno / trabajo pendiente'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Próximo turno / trabajo pendiente'),
        'Instalar sello y probar la presión.',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await reach(tester, find.text('Publicar nota'));
      await captureFleet(tester, 'coordination-handover-keyboard-es-large');
      expect(
        tester.getBottomRight(find.byKey(const Key('post-coordination'))).dy,
        lessThanOrEqualTo(844 - 280),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'rejected photo upload keeps input editable so the photo can be removed',
    (tester) async {
      final repository = FixtureCoordination()
        ..uploadError = const StorageException(
          'File too large',
          statusCode: '413',
        );
      await pumpCoordination(
        tester,
        const DiscussionWriteScreen(
          subject: (kind: 'job', id: 'job'),
          title: 'Repair cooling leak',
          providerTeam: false,
        ),
        repository,
        composer: true,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'What happened / current situation'),
        'Pump isolated.',
      );
      await reach(tester, find.text('Gallery'));
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      await reach(tester, find.text('Post note'));
      await tester.tap(find.text('Post note'));
      await tester.pumpAndSettle();
      expect(repository.writes, isEmpty);
      await reach(tester, find.byTooltip('Remove photo'));
      await tester.tap(find.byTooltip('Remove photo'));
      await tester.pumpAndSettle();
      await reach(tester, find.text('Post note'));
      await tester.tap(find.text('Post note'));
      await tester.pumpAndSettle();
      expect(repository.writes.single.data['body'], 'Pump isolated.');
      expect(repository.writes.single.data['attachments'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('home presents three separate actionable priorities', (
    tester,
  ) async {
    await pumpCoordination(
      tester,
      Scaffold(body: ListView(children: const [FleetPriorityCard()])),
      FixtureCoordination(),
    );
    expect(find.byType(AttentionTile), findsNWidgets(3));
    await captureFleet(tester, 'coordination-home-priorities-en');
    expect(tester.takeException(), isNull);
  });
}
