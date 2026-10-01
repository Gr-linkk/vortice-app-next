import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maintenance_local/agent_service/agent_service.dart';
import 'package:maintenance_local/agent_service/grants.dart';
import 'package:maintenance_local/agent_service/proposal_review.dart';
import 'package:maintenance_local/lab_store.dart';
import 'package:maintenance_local/model.dart';
import 'package:maintenance_local/src/rust/frb_generated.dart';
import 'package:maintenance_local/ui/agent_proposals_page.dart';

const _boundary = Key('agent-proposal-render');
const _suggestion =
    'Check the guard clearance before the next inspection.\n'
    '<script>Untrusted agent text is displayed literally.</script>';

class _SyntheticGrant implements GrantProvider {
  _SyntheticGrant(this.grant);
  final AgentGrant grant;
  @override
  Future<AgentGrant?> resolve(String token) async =>
      token == 'synthetic-render-token' ? grant : null;
}

/// Fault injection occurs after the actual office command commits. No domain
/// result is fabricated: the retry must obtain the real durable receipt.
class _LostReplyReviewer extends AgentProposalReviewer {
  _LostReplyReviewer({
    required super.store,
    required super.workspaceId,
    required super.serviceDeviceId,
  });
  bool loseOnce = true;
  final operationIds = <String>[];
  @override
  Future<Json> decide(
    NotesProposalView view, {
    required String operationId,
    required bool accept,
    String reason = '',
  }) async {
    operationIds.add(operationId);
    final receipt = await super.decide(
      view,
      operationId: operationId,
      accept: accept,
      reason: reason,
    );
    if (loseOnce) {
      loseOnce = false;
      throw const FileSystemException('Synthetic lost command reply');
    }
    return receipt;
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 400));
  expect(
    tester.takeException(),
    isNull,
    reason: 'Phone and large text must render without layout errors.',
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['VORTICE_RENDER_OUTPUT'];
  if (output == null || output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

Future<void> _mount(
  WidgetTester tester,
  AgentProposalReviewer reviewer,
  double scale,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff7f4ed),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff103d3c),
            primary: const Color(0xff103d3c),
            surface: const Color(0xfff7f4ed),
          ),
          cardTheme: const CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.symmetric(vertical: 8),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AgentProposalsPage(reviewer: reviewer),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        Platform.environment['MAINTENANCE_NATIVE_LIBRARY']!,
      ),
    );
    for (final face in ['Regular', 'Bold']) {
      await (FontLoader('Roboto')..addFont(
            File(
              '../../assets/fonts/Roboto-$face.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late Directory root;
  late LabStore store;
  late AgentService service;
  late String job;
  final clock = DateTime.utc(2026, 10, 1, 12);
  Json request(Json args) => {
    'protocol_version': 1,
    'request_id': 'synthetic-render-request',
    'scope': {
      'workspace_id': 'synthetic-render-workspace',
      'company_id': store.catalog!['companyId'],
      'device_id': store.device,
    },
    'credential': {'token': 'synthetic-render-token'},
    'command': 'proposals.create',
    'args': args,
  };
  Future<void> propose(String key) async {
    final response = await service.handle(
      request({
        'type': 'inspection.notes',
        'job_id': job,
        'expected_document_hash': digest(store.documentFor(job)!),
        'notes': _suggestion,
        'idempotency_key': key,
      }),
    );
    expect(response['ok'], true, reason: canonical(response));
    expect(response['result']['item']['status'], 'pending_human_review');
    expect(response['result']['item']['applied'], false);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agent-review-render-');
    store = await LabStore.open(
      Directory('${root.path}/office'),
      office: true,
      now: () => clock,
      maintenanceOnly: true,
    );
    await store.createCompany('Synthetic review company');
    final equipment = await store.addEquipment(
      name: 'Synthetic workshop compressor',
      meterUnit: 'none',
    );
    final procedure = await store.publishChecklist(
      title: 'Synthetic guard inspection',
      items: [
        {'id': 'guard', 'label': 'Inspect guard', 'input_type': 'check'},
      ],
    );
    job =
        (await store.prepareWork(
              equipmentId: equipment['id'] as String,
              templateId: procedure['id'] as String,
              title: 'Weekly inspection',
            ))['id']
            as String;
    await store.update({
      'notes': 'Mechanic recorded the original guard condition.',
    }, jobId: job);
    service = AgentService(
      store: store,
      workspaceId: 'synthetic-render-workspace',
      serviceDeviceId: store.device,
      grants: _SyntheticGrant(
        AgentGrant(
          id: 'synthetic-render-grant',
          actorId: 'Workshop helper',
          workspaceId: 'synthetic-render-workspace',
          companyId: store.catalog!['companyId'] as String,
          deviceId: store.device,
          expiresAt: clock.add(const Duration(hours: 1)),
          commands: AgentService.commands,
          jobIds: {job},
        ),
      ),
      now: () => clock,
    );
  });
  void cleanup(WidgetTester tester) => addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Drain the adapter's fake-zone future chain before crossing to real file
    // I/O. Waiting for that chain inside runAsync prevents fake microtasks from
    // advancing and deadlocks the test even though the command has completed.
    final closing = store.close();
    await tester.pump();
    await closing;
    await tester.runAsync(() async {
      await root.delete(recursive: true);
    });
  });

  for (final scale in [1.0, 1.8, 2.0]) {
    final name = switch (scale) {
      1.0 => 'phone',
      1.8 => 'large-text',
      _ => 'large-text-2x',
    };
    testWidgets(
      'actual office applies notes with confirmation and safe retry: $name',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(412, 915);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        cleanup(tester);
        await tester.runAsync(
          () => propose('11111111-1111-4111-8111-111111111111'),
        );
        final reviewer = _LostReplyReviewer(
          store: store,
          workspaceId: 'synthetic-render-workspace',
          serviceDeviceId: store.device,
        );
        await _mount(tester, reviewer, scale);
        expect(find.text('Agent suggestions'), findsOneWidget);
        await _capture(tester, '$name-pending');
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Review suggested notes'),
        );
        expect(find.text('Current draft notes'), findsOneWidget);
        expect(find.text(_suggestion), findsOneWidget);
        expect(
          find.text('Mechanic recorded the original guard condition.'),
          findsOneWidget,
        );
        await _capture(tester, '$name-review');
        await _tap(
          tester,
          find.widgetWithText(FilledButton, 'Apply to draft notes'),
        );
        expect(find.text('Apply suggested notes?'), findsOneWidget);
        expect(store.agentNotesReviews, isEmpty);
        await _capture(tester, '$name-confirm');
        await _tap(
          tester,
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Apply to draft notes'),
          ),
        );
        expect(find.text('Retry same decision'), findsOneWidget);
        expect(store.agentNotesReviews, hasLength(1));
        await tester.ensureVisible(
          find.textContaining('The result could not be confirmed.'),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await _capture(tester, '$name-uncertain');
        await _tap(
          tester,
          find.widgetWithText(FilledButton, 'Retry same decision'),
        );
        expect(reviewer.operationIds, hasLength(2));
        expect(reviewer.operationIds[1], reviewer.operationIds[0]);
        expect(store.agentNotesReviews, hasLength(1));
        expect(
          find.textContaining('Saved locally. Draft notes updated.'),
          findsOneWidget,
        );
        expect(store.submissions, isEmpty);
        expect(store.receipts, isEmpty);
        final values = await tester.runAsync(() => store.fields(jobId: job));
        expect(values!['notes'], contains(_suggestion));
        await _capture(tester, '$name-applied');
        await _tap(tester, find.byType(BackButton));
        expect(
          find.text('No suggested notes are waiting for review.'),
          findsOneWidget,
        );
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'View review record'),
        );
        expect(find.text('Review record'), findsOneWidget);
        expect(find.text(_suggestion), findsOneWidget);
        await _capture(tester, '$name-history');
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      },
    );

    testWidgets(
      'stale suggestion cannot apply, rejection history needs no pending files: $name',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(412, 915);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        cleanup(tester);
        await tester.runAsync(() async {
          await propose('22222222-2222-4222-8222-222222222222');
          await store.update({
            'notes': 'A mechanic saved newer inspection notes.',
          }, jobId: job);
        });
        final reviewer = AgentProposalReviewer(
          store: store,
          workspaceId: 'synthetic-render-workspace',
          serviceDeviceId: store.device,
        );
        await _mount(tester, reviewer, scale);
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Review suggested notes'),
        );
        final apply = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Apply to draft notes'),
        );
        expect(apply.onPressed, isNull);
        expect(find.textContaining('cannot be applied'), findsOneWidget);
        await _capture(tester, '$name-stale');
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Reject with reason'),
        );
        final reason = find.widgetWithText(TextField, 'Reason for rejection');
        await tester.enterText(
          reason,
          'The mechanic recorded newer information.',
        );
        await _settle(tester);
        await _capture(tester, '$name-reject-reason');
        await _tap(tester, find.widgetWithText(FilledButton, 'Continue'));
        expect(store.agentNotesReviews.single['decision'], 'rejected');
        final values = await tester.runAsync(() => store.fields(jobId: job));
        expect(
          values!['notes'],
          contains('A mechanic saved newer inspection notes.'),
        );
        expect(
          find.text('Rejected and saved locally. Draft notes are unchanged.'),
          findsOneWidget,
        );
        await _tap(tester, find.byType(BackButton));
        await tester.runAsync(() async {
          await Directory(
            '${store.root.path}/agent-proposals-v1',
          ).delete(recursive: true);
        });
        await _tap(
          tester,
          find.widgetWithText(TextButton, 'Refresh suggestions'),
        );
        expect(
          find.text('No suggested notes are waiting for review.'),
          findsOneWidget,
        );
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'View review record'),
        );
        expect(
          find.text('The mechanic recorded newer information.'),
          findsOneWidget,
        );
        expect(find.text(_suggestion), findsOneWidget);
        await _capture(tester, '$name-rejected-history');
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      },
    );
  }
  testWidgets(
    'refresh after external review shows immutable receipt, not later live notes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      cleanup(tester);
      await tester.runAsync(
        () => propose('33333333-3333-4333-8333-333333333333'),
      );
      final reviewer = AgentProposalReviewer(
        store: store,
        workspaceId: 'synthetic-render-workspace',
        serviceDeviceId: store.device,
      );
      await _mount(tester, reviewer, 1);
      await _tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Review suggested notes'),
      );
      expect(find.text('Current draft notes'), findsOneWidget);
      var reviewed = false;
      final externalReview = () async {
        final proposal = (await reviewer.pending()).single;
        final view = await reviewer.show(proposal.id);
        await reviewer.decide(
          view,
          operationId: '44444444-4444-4444-8444-444444444444',
          accept: true,
        );
        await store.update({
          'notes':
              'Later live draft notes must never appear as historical reviewed notes.',
        }, jobId: job);
        reviewed = true;
      }();
      // The visible adapter already has a fake-zone queue tail. Pump both native
      // callbacks and fake microtasks while another office caller reviews it.
      for (var i = 0; i < 20 && !reviewed; i++) {
        await _settle(tester);
      }
      expect(reviewed, isTrue);
      await externalReview;
      await _tap(
        tester,
        find.widgetWithText(TextButton, 'Refresh current notes'),
      );
      expect(find.text('Review record'), findsOneWidget);
      expect(find.text('Reviewed suggested notes'), findsOneWidget);
      expect(find.text(_suggestion), findsOneWidget);
      expect(find.text('Current draft notes'), findsNothing);
      expect(find.text('Draft notes reviewed'), findsNothing);
      expect(find.textContaining('Later live draft notes'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Apply to draft notes'),
        findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Reject with reason'),
        findsNothing,
      );
      expect(
        find.widgetWithText(TextButton, 'Refresh current notes'),
        findsNothing,
      );
      await _capture(tester, 'phone-refreshed-terminal-history');
    },
  );
}
