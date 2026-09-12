import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/parts_readiness_models.dart';
import 'package:vortice_app/features/parts/parts_readiness_repository.dart';
import 'package:vortice_app/features/parts/parts_readiness_screen.dart';
import 'package:vortice_app/features/parts/work_parts_progress.dart';

class FixtureParts implements PartsReadinessRepository {
  FixtureParts({this.manager = true, this.fail = false});
  final bool manager;
  bool fail;
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> pending() async => null;
  @override
  Future<void> retry() async {}
  @override
  Future<void> change(
    String? jobId,
    String action,
    Map<String, dynamic> data,
  ) async {
    calls.add({'job': jobId, 'action': action, 'data': data});
  }

  @override
  Future<PartsWorkspace> load(String? jobId) async {
    if (fail) throw StateError('Offline');
    return PartsWorkspace({
      'can_manage': manager,
      'can_change': true,
      'can_issue': true,
      'job_title': 'Friday generator service',
      'kit_captured': true,
      'has_kit': true,
      'stock': [
        {
          'id': 'stock',
          'description': 'Generator oil filter',
          'location': 'Main workshop',
          'unit': 'ea',
          'qty_on_hand': 1,
          'reserved': 0,
          'min_stock_level': 2,
          'revision': 1,
        },
      ],
      'requirements': [
        {
          'id': 'requirement',
          'description': 'Generator oil filter',
          'required_qty': 2,
          'stock_id': 'stock',
          'reserved_qty': 0,
          'used_qty': 0,
          'revision': 1,
        },
      ],
      'purchases': [],
      'events': [],
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  FixtureParts repository, {
  bool es = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        partsReadinessRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: es ? AppTheme.darkTheme : AppTheme.lightTheme,
        locale: Locale(es ? 'es' : 'en'),
        supportedLocales: const [Locale('en'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const PartsReadinessScreen(jobId: 'job'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('closing parts after the originating work is removed is safe', (
    tester,
  ) async {
    final showWork = ValueNotifier(true);
    addTearDown(showWork.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partsReadinessRepositoryProvider.overrideWithValue(FixtureParts()),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showWork,
              builder: (_, visible, child) => visible
                  ? const WorkPartsProgress(jobId: 'job')
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review parts'));
    await tester.pumpAndSettle();
    expect(find.byType(PartsReadinessScreen), findsOneWidget);
    showWork.value = false;
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'job shows shortage and reserves explicit quantity through the native form',
    (tester) async {
      final repository = FixtureParts();
      await _pump(tester, repository);
      expect(find.text('Shortage: 1 ea'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reserve parts'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '1'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '-1');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      await tester.enterText(find.byType(TextFormField), '1');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.calls.single['action'], 'reserve');
      expect((repository.calls.single['data'] as Map)['quantity'], 1);
      expect(tester.takeException(), isNull);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('Spanish large text stock and orders render without overflow', (
    tester,
  ) async {
    await _pump(tester, FixtureParts(), es: true, scale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Existencias').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existencias').first);
    await tester.pumpAndSettle();
    expect(find.text('Por debajo del mínimo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Pedidos').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedidos').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('assigned mechanic cannot edit stock or requirements', (
    tester,
  ) async {
    await _pump(tester, FixtureParts(manager: false));
    expect(find.text('Add requirement'), findsNothing);
    expect(find.text('Reserve parts'), findsNothing);
    await tester.tap(find.text('Stock').first);
    await tester.pumpAndSettle();
    expect(find.text('Count / adjust'), findsNothing);
    expect(find.text('Add stock item'), findsNothing);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets(
    'offline state does not report zero stock and recovers on retry',
    (tester) async {
      final repository = FixtureParts(fail: true);
      await _pump(tester, repository);
      expect(
        find.textContaining('Current stock is unavailable'),
        findsOneWidget,
      );
      expect(find.text('Requirement covered'), findsNothing);
      repository.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Shortage: 1 ea'), findsOneWidget);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
