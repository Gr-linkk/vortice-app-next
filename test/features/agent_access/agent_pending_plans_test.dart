import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/agent_access/agent_pending_plans_screen.dart';

void main() {
  testWidgets('review inbox pages proposals independently of activity', (
    tester,
  ) async {
    final requests = <int>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingAgentPlansProvider.overrideWith((ref, key) async {
            requests.add(key.$2);
            return key.$2 == 0
                ? List.generate(
                    26,
                    (i) => {
                      'id': 'proposal-$i',
                      'assets': {'name': 'Machine $i'},
                      'draft': {
                        'interval_label': 'Service $i',
                        'interval_hours': 250,
                      },
                    },
                  )
                : [];
          }),
        ],
        child: const MaterialApp(home: AgentPendingPlansScreen(fleet: 'fleet')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Service 0'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Next'), 500);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('No proposals on this page.'), findsOneWidget);
    expect(requests, [0, 1]);
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('Service 0'), findsOneWidget);
  });

  testWidgets('failed inbox load has a working retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingAgentPlansProvider.overrideWith((ref, key) async {
            if (attempts++ == 0) throw StateError('offline');
            return [];
          }),
        ],
        child: const MaterialApp(home: AgentPendingPlansScreen(fleet: 'fleet')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Could not load. Retry.'));
    await tester.pumpAndSettle();
    expect(find.text('No proposals on this page.'), findsOneWidget);
    expect(attempts, 2);
  });
}
