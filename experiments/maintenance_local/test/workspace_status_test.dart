import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/local_sync.dart';
import 'package:maintenance_local/ui/workspace_page.dart';

// Uses actual company, equipment, snapshot and per-job documents. Only the
// transport below is injected; local persistence and status projection are real.
Future<LabStore> _store(WidgetTester tester, {String? photoError}) async {
  late Directory root;
  final phone = await tester.runAsync(() async {
    root = await Directory.systemTemp.createTemp('maintenance-status-');
    final office = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      maintenanceOnly: true,
    );
    await OfficeIdentity.load(office);
    await office.createCompany(
      'Synthetic maintenance company',
      coordinatorName: 'Sam Coordinator',
    );
    final equipment = await office.addEquipment(
      name: 'Synthetic status generator',
    );
    final template = await office.publishChecklist(
      title: 'Daily safety checks',
      items: [
        {'id': 'guards', 'label': 'Inspect guards', 'input_type': 'check'},
      ],
      provenance: {'kind': 'company-authored'},
    );
    await office.prepareWork(
      equipmentId: equipment['id'] as String,
      templateId: template['id'] as String,
      title: 'Daily inspection',
    );
    final phone = await LabStore.open(
      Directory('${root.path}/phone'),
      office: false,
      maintenanceOnly: true,
    );
    await phone.importOfficeBundle(await office.publicBundle());
    await office.close();
    if (photoError != null) phone.setSetting('photoRecoveryError', photoError);
    return phone;
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await phone!.close();
      await root.delete(recursive: true);
    });
  });
  return phone!;
}

// Retains PhoneSync's real visibleMessage presentation; transport alone is fake.
class StatusSync extends PhoneSync {
  StatusSync(super.store);
  bool fail = true;
  bool pending = false;
  bool preserveFailureMessage = false;
  Completer<void>? attemptGate;
  Object enrollmentFailure = const SocketException(
    'Synthetic enrollment failure',
  );
  Completer<void>? enrollmentGate;
  bool enrollmentSucceeds = false;
  @override
  Future<void> enroll(
    String invitation, {
    String label = 'Inspection phone',
  }) async {
    final gate = enrollmentGate;
    enrollmentGate = null;
    if (gate != null) await gate.future;
    if (enrollmentSucceeds) {
      lastGuidance = null;
      connectionResponses++;
      message = 'Confirm code 123456 on the computer.';
      onChange?.call();
      return;
    }
    throw enrollmentFailure;
  }

  int calls = 0;
  @override
  Future<void> sync() async {
    if (busy) return;
    busy = true;
    calls++;
    onChange?.call();
    try {
      final gate = attemptGate;
      attemptGate = null;
      if (gate != null) await gate.future;
      if (fail) {
        const error = SocketException('Synthetic unreachable fixture');
        lastGuidance = connectionGuidance(error);
        if (!preserveFailureMessage) message = lastGuidance!.message;
        throw error;
      }
      lastGuidance = null;
      connectionResponses++;
      message = pending
          ? 'Confirm code 123456 on the computer.'
          : 'Connected to the computer.';
    } finally {
      busy = false;
      onChange?.call();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        File(
          Platform.environment['MAINTENANCE_NATIVE_LIBRARY'] ??
              'rust/target/debug/librust_lib_sync_lab.so',
        ).absolute.path,
      ),
    );
  });
  for (final scale in [1.0, 2.0]) {
    Future<void> open(
      WidgetTester tester,
      LabStore store,
      StatusSync sync,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: WorkspacePage(store: store, phoneSyncFactory: (_) => sync),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    Future<void> manualSync(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    Future<void> updateConnection(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Update computer connection'));
      await tester.tap(find.text('Update computer connection'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Copying on the computer alone'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'SYNTHETIC INVITATION');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    if (scale == 1.0) {
      testWidgets(
        'failed connection update keeps help until a new response, despite old confirmation text',
        (tester) async {
          final store = await _store(tester);
          final sync = StatusSync(store)
            ..message = 'Confirm code 123456 on the computer.'
            ..preserveFailureMessage = true;
          await open(tester, store, sync);
          await tester.ensureVisible(find.text('Update computer connection'));
          await tester.tap(find.text('Update computer connection'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField),
            'SYNTHETIC INVALID INVITATION',
          );
          await tester.ensureVisible(find.text('Continue'));
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          expect(sync.connectionResponses, 0);
          expect(sync.message, 'Confirm code 123456 on the computer.');
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsOneWidget,
          );
          final gate = Completer<void>();
          sync.attemptGate = gate;
          await tester.pump(const Duration(seconds: 4));
          await tester.pump();
          // Beginning a retry and old confirmation text prove no new response.
          expect(sync.lastGuidance, isNull);
          expect(sync.connectionResponses, 0);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsOneWidget,
          );
          gate.complete();
          await tester.pump();
          await tester.pump();
          expect(sync.connectionResponses, 0);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsWidgets,
          );
          sync.fail = false;
          await tester.pump(const Duration(seconds: 4));
          await tester.pump();
          expect(sync.connectionResponses, 1);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsNothing,
          );
          expect(find.text('More connection help'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
      testWidgets(
        'a retry keeps its transport banner until an actual response',
        (tester) async {
          final store = await _store(tester);
          final sync = StatusSync(store);
          await open(tester, store, sync);
          await updateConnection(tester);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsOneWidget,
          );
          final gate = Completer<void>();
          sync.enrollmentGate = gate;
          sync.enrollmentSucceeds = true;
          await updateConnection(tester);
          expect(sync.connectionResponses, 0);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Update computer connection'),
                )
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Sync now'),
                )
                .onPressed,
            isNull,
          );
          await tester.pump(const Duration(seconds: 4));
          expect(
            sync.calls,
            0,
            reason: 'Enrollment and background sync must not overlap.',
          );
          gate.complete();
          await tester.pump();
          await tester.pump();
          expect(sync.connectionResponses, 1);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsNothing,
          );
          expect(
            find.text('Confirm code 123456 on the computer.'),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 2));
        },
      );
      testWidgets(
        'application and photo errors survive connection retry and success',
        (tester) async {
          const applicationError =
              'Different company. Your saved work has been retained.';
          const photoError =
              'The interrupted photo could not be recovered. Choose the photo again.';
          final store = await _store(tester, photoError: photoError);
          final sync = StatusSync(store)
            ..enrollmentFailure = StateError(applicationError);
          await open(tester, store, sync);
          await updateConnection(tester);
          expect(find.text(applicationError), findsOneWidget);
          expect(find.text(photoError), findsOneWidget);
          sync.enrollmentFailure = const SocketException(
            'Synthetic retry failure',
          );
          await updateConnection(tester);
          expect(find.text(applicationError), findsOneWidget);
          expect(find.text(photoError), findsOneWidget);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsOneWidget,
          );
          sync.fail = false;
          await tester.pump(const Duration(seconds: 4));
          await tester.pump();
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsNothing,
          );
          expect(find.text(applicationError), findsOneWidget);
          expect(find.text(photoError), findsOneWidget);
          expect(store.setting('photoRecoveryError'), photoError);
          // A real gallery recovery clears this persisted setting, not transport.
          store.setSetting('photoRecoveryError', null);
          sync.onChange?.call();
          await tester.pump();
          expect(find.text(photoError), findsNothing);
          expect(find.text(applicationError), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
      testWidgets('an initially inactive phone waits until resumed', (
        tester,
      ) async {
        final store = await _store(tester);
        final sync = StatusSync(store)..fail = false;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await open(tester, store, sync);
        await tester.pump(const Duration(seconds: 4));
        expect(sync.calls, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(sync.calls, 1);
        expect(find.text('Connected to the computer.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
      testWidgets('an existing automatic exchange blocks connection updates', (
        tester,
      ) async {
        final store = await _store(tester);
        final sync = StatusSync(store)..attemptGate = Completer<void>();
        final gate = sync.attemptGate!;
        await open(tester, store, sync);
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(sync.busy, isTrue);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Update computer connection'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Sync now'),
              )
              .onPressed,
          isNull,
        );
        gate.complete();
        await tester.pump();
        await tester.pump();
        expect(sync.busy, isFalse);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Update computer connection'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
      testWidgets(
        'manual invitation entry fences automatic sync until cancelled',
        (tester) async {
          final store = await _store(tester);
          final sync = StatusSync(store)..fail = false;
          await open(tester, store, sync);
          await tester.ensureVisible(find.text('Update computer connection'));
          await tester.tap(find.text('Update computer connection'));
          await tester.pumpAndSettle();
          expect(find.text('Paste computer invitation'), findsOneWidget);
          await tester.pump(const Duration(seconds: 8));
          expect(sync.calls, 0);
          await tester.ensureVisible(find.text('Cancel'));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 4));
          await tester.pump();
          expect(sync.calls, 1);
          expect(find.text('Connected to the computer.'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
      testWidgets(
        'an application error does not orphan earlier transport guidance',
        (tester) async {
          const applicationError =
              'Different company. Your saved work has been retained.';
          final store = await _store(tester);
          final sync = StatusSync(store);
          await open(tester, store, sync);
          await updateConnection(tester);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsOneWidget,
          );
          sync.enrollmentFailure = StateError(applicationError);
          await updateConnection(tester);
          expect(find.text(applicationError), findsOneWidget);
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsOneWidget,
          );
          sync.fail = false;
          await tester.pump(const Duration(seconds: 4));
          await tester.pump();
          expect(
            find.textContaining('Cannot reach the computer.'),
            findsNothing,
          );
          expect(find.text(applicationError), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
      for (final entry in <String, Object>{
        'identity': const HandshakeException('Synthetic identity diagnostic'),
        'incomplete': const FormatException('Synthetic malformed invitation'),
      }.entries) {
        testWidgets(
          '${entry.key} guidance clears only after a fresh successful response',
          (tester) async {
            final store = await _store(tester);
            final sync = StatusSync(store)..enrollmentFailure = entry.value;
            await open(tester, store, sync);
            await updateConnection(tester);
            final message = connectionGuidance(entry.value)!.message;
            expect(find.textContaining(message), findsOneWidget);
            sync.fail = false;
            await tester.pump(const Duration(seconds: 4));
            await tester.pump();
            expect(sync.connectionResponses, 1);
            expect(find.textContaining(message), findsNothing);
            expect(find.text('Connected to the computer.'), findsOneWidget);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
    testWidgets(
      'manual failure then timer recovery shows one safe status at ${scale}x',
      (tester) async {
        final store = await _store(tester);
        final sync = StatusSync(store);
        await open(tester, store, sync);
        await manualSync(tester);
        expect(sync.calls, 1);
        expect(
          find.text('Saved on this phone—waiting to send.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Cannot reach the computer.'),
          findsOneWidget,
        );
        expect(find.text('More connection help'), findsOneWidget);
        sync.fail = false;
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(sync.calls, 2);
        expect(find.text('Connected to the computer.'), findsOneWidget);
        expect(find.textContaining('Cannot reach the computer.'), findsNothing);
        expect(find.text('More connection help'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'same-office pending confirmation replaces stale failure at ${scale}x',
      (tester) async {
        final store = await _store(tester);
        final sync = StatusSync(store);
        await open(tester, store, sync);
        await manualSync(tester);
        sync.fail = false;
        sync.pending = true;
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(
          find.text('Confirm code 123456 on the computer.'),
          findsOneWidget,
        );
        expect(find.textContaining('Cannot reach the computer.'), findsNothing);
        expect(find.text('More connection help'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'independent photo recovery error survives manual failure and later success at ${scale}x',
      (tester) async {
        const photoError =
            'The interrupted photo could not be recovered. Choose the photo again.';
        final store = await _store(tester, photoError: photoError);
        final sync = StatusSync(store);
        await open(tester, store, sync);
        expect(find.text(photoError), findsOneWidget);
        await manualSync(tester);
        expect(find.text(photoError), findsOneWidget);
        expect(
          find.textContaining('Cannot reach the computer.'),
          findsOneWidget,
        );
        sync.fail = false;
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(find.text(photoError), findsOneWidget);
        expect(find.text('Connected to the computer.'), findsOneWidget);
        expect(find.textContaining('Cannot reach the computer.'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
