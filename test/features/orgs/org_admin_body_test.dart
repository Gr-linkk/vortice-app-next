import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/orgs/org_admin_body.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/models/client_org.dart';

void main() {
  testWidgets(
    'Team contains membership and invitations without duplicate work tabs',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orgMembersProvider('org-1').overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: OrgAdminBody(
              org: ClientOrg(
                id: 'org-1',
                name: 'Harbour team',
                ownerProfileId: 'owner-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Team · Harbour team'), findsOneWidget);
      expect(find.text('Invite team member'), findsOneWidget);
      expect(find.text('No team members yet.'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Fleet'), findsNothing);
      expect(find.text('Invoices'), findsNothing);
    },
  );
}
