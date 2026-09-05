import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/fleet/availability_screen.dart';
import 'package:vortice_app/features/fleet/fault_detail_screen.dart';
import 'package:vortice_app/features/fleet/fault_report_screen.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';
import 'package:vortice_app/features/fleet/fleet_screen.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';

class FixtureFleetRepository implements FleetRepository {
  List<FleetAsset> assets = [
    FleetAsset(
      id: 'pump',
      name: 'Hydraulic Pump 04',
      location: 'North workshop',
      state: OperatingState.outOfService,
      reason: 'Hydraulic leak — isolated for repair',
      changedAt: DateTime.utc(2026, 9, 5, 9),
      changedByName: 'Alex Morgan',
      downtimeSeconds: 7200,
      revision: 2,
      openFaults: 1,
      urgentFaults: 1,
    ),
    const FleetAsset(
      id: 'generator',
      name: 'Standby Generator',
      location: 'Dock 2',
      state: OperatingState.available,
      reason: 'Weekly inspection complete',
      revision: 1,
    ),
    const FleetAsset(
      id: 'loader',
      name: 'Wheel Loader 12',
      location: 'Yard',
      openFaults: 1,
    ),
  ];
  List<FleetFault> items = [
    FleetFault(
      id: 'fault-1',
      assetId: 'pump',
      assetName: 'Hydraulic Pump 04',
      description: 'Hydraulic oil leaking around the main pump seal',
      status: FaultStatus.pendingReview,
      urgent: true,
      assignedTo: 'mechanic',
      assigneeName: 'Jordan Lee',
      reporterName: 'Sam Rivera',
      revision: 3,
      createdAt: DateTime.utc(2026, 9, 5, 8),
      updatedAt: DateTime.utc(2026, 9, 5, 11),
    ),
    FleetFault(
      id: 'fault-2',
      assetId: 'loader',
      assetName: 'Wheel Loader 12',
      description: 'Work light flickers during the morning inspection',
      status: FaultStatus.open,
      createdAt: DateTime.utc(2026, 9, 5, 7),
    ),
  ];
  Object? readError;
  Object? nextReportError;
  Object? nextMutationError;
  final reportIds = <String>[];
  final mutations = <FaultAction>[];
  String? lastNote;
  OperatingState? lastState;
  bool reportUrgent = false;

  @override
  Future<List<FleetAsset>> fleet() async {
    if (readError != null) throw readError!;
    return assets;
  }

  @override
  Future<List<FleetFault>> faults({String? assetId, String? faultId}) async {
    if (readError != null) throw readError!;
    return items
        .where(
          (f) =>
              (assetId == null || f.assetId == assetId) &&
              (faultId == null || f.id == faultId),
        )
        .toList();
  }

  @override
  Future<List<FleetEvent>> faultEvents(String faultId) async => [
    FleetEvent(
      id: 'event-2',
      kind: 'submit',
      fromState: 'in_progress',
      toState: 'pending_review',
      note:
          'Replaced the seal and pressure tested. Ready for supervisor review.',
      actorName: 'Jordan Lee',
      createdAt: DateTime.utc(2026, 9, 5, 11),
    ),
    FleetEvent(
      id: 'event-1',
      kind: 'reported',
      toState: 'open',
      note: 'Oil leak found during pre-start checks.',
      actorName: 'Sam Rivera',
      createdAt: DateTime.utc(2026, 9, 5, 8),
    ),
  ];
  @override
  Future<List<FleetEvent>> availabilityEvents(String assetId) async => [
    FleetEvent(
      id: 'state-1',
      kind: 'availability',
      fromState: 'available',
      toState: 'out_of_service',
      note: 'Hydraulic leak — isolated for repair',
      actorName: 'Alex Morgan',
      createdAt: DateTime.utc(2026, 9, 5, 9),
    ),
  ];
  @override
  Future<List<FleetMember>> assignees(String assetId) async => [
    const FleetMember(
      id: 'mechanic',
      name: 'Jordan Lee',
      role: 'client_mechanic',
    ),
  ];
  @override
  Future<String> report({
    required String requestId,
    required String assetId,
    required String description,
    required bool urgent,
  }) async {
    reportIds.add(requestId);
    final error = nextReportError;
    nextReportError = null;
    if (error != null) throw error;
    reportUrgent = urgent;
    items.add(
      FleetFault(
        id: requestId,
        assetId: assetId,
        assetName: 'Hydraulic Pump 04',
        description: description,
      ),
    );
    return requestId;
  }

  @override
  Future<void> updateFault({
    required FleetFault fault,
    required String operationId,
    required FaultAction action,
    required String note,
    String? assignedTo,
  }) async {
    final error = nextMutationError;
    nextMutationError = null;
    if (error != null) throw error;
    mutations.add(action);
    lastNote = note;
  }

  @override
  Future<void> changeAvailability({
    required FleetAsset asset,
    required String operationId,
    required OperatingState state,
    required String reason,
  }) async {
    final error = nextMutationError;
    nextMutationError = null;
    if (error != null) throw error;
    lastState = state;
    lastNote = reason;
  }
}

Future<void> loadFleetScreenshotFonts() async {
  final root = Platform.environment['VORTICE_FLUTTER_FONTS'];
  if (root == null) return;
  final font = FontLoader('Roboto');
  for (final name in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final bytes = await File('$root/$name').readAsBytes();
    font.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          await File('$root/MaterialIcons-Regular.otf').readAsBytes(),
        ),
      ),
    );
  await icons.load();
}

Future<void> pumpFleet(
  WidgetTester tester,
  Widget home,
  FixtureFleetRepository repository, {
  UserRole role = UserRole.client,
  String userId = 'manager',
  String language = 'en',
  double textScale = 1,
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(path: '/fleet', builder: (_, __) => const FleetScreen()),
      GoRoute(
        path: '/fleet/report',
        builder: (_, __) => const FaultReportScreen(),
      ),
      GoRoute(
        path: '/fleet/faults/:id',
        builder: (_, s) => FaultDetailScreen(faultId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/fleet/assets/:id',
        builder: (_, s) => AvailabilityScreen(assetId: s.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fleetRepositoryProvider.overrideWithValue(repository),
        profileProvider.overrideWith(
          (ref) async => Profile(
            id: userId,
            email: 'fixture@example.invalid',
            fullName: 'Alex Morgan',
            role: role,
          ),
        ),
      ],
      child: RepaintBoundary(
        key: const Key('fleet-capture'),
        child: MaterialApp.router(
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
              labelStyle: const TextStyle(
                fontFamily: 'Roboto',
                color: AppColors.textPrimary,
              ),
            ),
          ),
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          locale: Locale(language),
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
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> captureFleet(WidgetTester tester, String name) async {
  final directory = Platform.environment['VORTICE_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('fleet-capture')),
  );
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
