import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/agent_access/agent_connection_setup.dart';
import 'package:vortice_app/features/agent_access/agent_work_proposals_screen.dart';
import 'package:vortice_app/features/agent_access/agent_review_evidence.dart';

class ReviewFixture extends AgentWorkProposalRepository {
  ReviewFixture() : super(SupabaseClient('https://example.invalid', 'fixture-public-key', authOptions: const AuthClientOptions(autoRefreshToken: false)), 'person');
  final calls = <({String proposal, String operation, String action})>[];
  bool failFirst = false;
  @override
  Future<void> review(String proposal, String operation, String action) async {
    calls.add((proposal: proposal, operation: operation, action: action));
    if (failFirst && calls.length == 1) throw StateError('Uncertain response');
  }
}

Map<String, dynamic> proposal({bool stale = false}) => {
  'id': 'proposal-a', 'work_order_id': 'job-a', 'action': 'assign_work_order',
  'work_title': 'Inspect hydraulic cooling system', 'asset_name': 'Truck 28', 'connection_label': 'My maintenance agent',
  'status': 'pending', 'can_apply': !stale, 'proposed_person': 'Morgan Mechanic', 'current_person': null,
  'input': {'assigned_to': 'person-a', 'revision': 0}, 'current': {'assigned_to': null},
};

Widget app(ReviewFixture repository, Map<String, dynamic> data, VoidCallback reviewed) => ProviderScope(
  overrides: [agentWorkProposalRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AgentWorkProposalCard(proposal: data, onReviewed: reviewed)))),
);

void main() {
  test('agent plan review keeps explicit units and blocks mismatched baselines', () {
    Map<String, dynamic> data(String unit) => {
      'proposal': {'draft': {'engine_id': 'engine', 'existing_plan_id': 'plan', 'interval_hours': 10000, 'meter_unit': 'km'}},
      'catalog': {'components': [{'id': 'engine', 'meter_unit': unit, 'current_hours': 62000}], 'plans': [{'id': 'plan', 'last_service_hours': 62000}]},
    };
    final km = AgentReviewEvidence(data('km'));
    expect(km.proposedDue, 72000);
    expect(reviewHours(km.proposedDue, km.unit), '72000 km');
    final changed = AgentReviewEvidence(data('mi'));
    expect(changed.meterMatches, false);
    expect(changed.proposedDue, isNull);
    expect(changed.canEdit, false);
  });
  testWidgets('human sees named current and proposed values; uncertain apply retries exact operation', (tester) async {
    final repository = ReviewFixture()..failFirst = true;
    var applied = 0;
    await tester.pumpWidget(app(repository, proposal(), () => applied++));
    expect(find.text('Current: Not set'), findsOneWidget);
    expect(find.text('Proposed: Morgan Mechanic'), findsOneWidget);
    expect(repository.calls, isEmpty);
    await tester.tap(find.text('Apply this change'));
    await tester.pumpAndSettle();
    expect(applied, 0);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Reject proposal')).onPressed, isNull);
    await tester.tap(find.text('Apply this change'));
    await tester.pumpAndSettle();
    expect(repository.calls.length, 2);
    expect(repository.calls[0].operation, repository.calls[1].operation);
    expect(applied, 1);
  });

  testWidgets('stale proposal disables application and can still be rejected', (tester) async {
    final repository = ReviewFixture();
    await tester.pumpWidget(app(repository, proposal(stale: true), () {}));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply this change')).onPressed, isNull);
    await tester.tap(find.text('Reject proposal'));
    await tester.pumpAndSettle();
    expect(repository.calls.single.action, 'reject');
  });

  testWidgets('guided setup explains host check and never embeds a connection secret', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AgentConnectionSetup(es: false)))));
    await tester.tap(find.text('Set up and test my agent'));
    await tester.pumpAndSettle();
    expect(find.textContaining('vortice_connection_test'), findsOneWidget);
    expect(find.textContaining('VORTICE_AGENT_TOKEN=<your private connection key>'), findsOneWidget);
    expect(find.textContaining('An open MCP connection alone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
