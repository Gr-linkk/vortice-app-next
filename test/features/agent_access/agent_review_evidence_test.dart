import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/agent_access/agent_review_evidence.dart';
import 'package:vortice_app/features/agent_access/maintenance_documents_repository.dart';

Map<String, dynamic> evidenceData({bool existing = true}) => {
  'proposal': {
    'asset_id': 'asset',
    'document_id': 'manual',
    'draft': {
      'interval_label': 'Cooling service',
      'engine_id': 'engine',
      'interval_hours': 250,
      if (existing) 'existing_plan_id': 'plan',
      'source_page': 2,
      'source_quote': 'Service the cooling system every 250 hours.',
    },
  },
  'document': {'title': 'Engine manual — revision 3'},
  'catalog': <String, dynamic>{
    'components': [
      {'id': 'engine', 'label': 'Main engine', 'current_hours': 400},
    ],
    'plans': [
      {'id': 'plan', 'interval_hours': 300, 'last_service_hours': 100},
    ],
  },
};

void main() {
  late MaintenanceDocumentPage source;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(16, 16);
    source = MaintenanceDocumentPage(
      (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
    image.dispose();
    picture.dispose();
  });
  test('proposal comparison uses this task baseline and live meter', () {
    final e = AgentReviewEvidence(evidenceData());
    expect(e.current, 400);
    expect(e.plan!['interval_hours'], 300);
    expect(e.proposedDue, 350);
    expect(e.proposedDue! - e.current!, -50);
    expect(e.canEdit, true);
  });
  test('new or missing plan never borrows another task baseline', () {
    final fresh = AgentReviewEvidence(evidenceData(existing: false));
    expect(fresh.baseline, isNull);
    expect(fresh.proposedDue, isNull);
    final data = evidenceData();
    data['catalog']['plans'] = [];
    final missing = AgentReviewEvidence(data);
    expect(missing.missingPlan, true);
    expect(missing.canEdit, false);
  });
  test('unpublished checklist and revoked planning access cannot edit', () {
    final data = evidenceData();
    data['proposal']['draft']['checklist_procedure_id'] = 'check';
    expect(AgentReviewEvidence(data).canEdit, false);
    data['procedure'] = {
      'published_template_id': 'template',
      'archived': false,
    };
    expect(AgentReviewEvidence(data).canEdit, true);
    data['catalog']['can_plan'] = false;
    expect(AgentReviewEvidence(data).canEdit, false);
  });
  testWidgets('source preview is deliberate and failed retrieval can retry', (
    tester,
  ) async {
    var reads = 0;
    final png = source.bytes;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentSourcePreviewProvider.overrideWith((ref, key) async {
            expect(key, ('manual', 2));
            if (reads++ == 0) throw StateError('offline');
            return MaintenanceDocumentPage(png);
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AgentSourceEvidence(
                  evidence: AgentReviewEvidence(evidenceData()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(png),
        tester.element(find.byType(Scaffold)),
      ),
    );
    expect(reads, 0);
    await tester.tap(find.text('View source page 2'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Could not load the page. Retry.'));
    await tester.tap(find.text('Could not load the page. Retry.'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Open full page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
