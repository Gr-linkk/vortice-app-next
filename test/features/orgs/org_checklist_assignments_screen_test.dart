import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/orgs/org_checklist_assignments_screen.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/client_org.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    UserRole role, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            (ref) async => Profile(
              id: 'profile-1',
              email: 'test@example.com',
              fullName: 'Pat',
              role: role,
              orgId: 'org-1',
            ),
          ),
          currentUserOrgProvider.overrideWith(
            (ref) async => const ClientOrg(
              id: 'org-1',
              name: 'Team',
              ownerProfileId: 'owner-1',
            ),
          ),
          orgChecklistAssignmentsProvider.overrideWith(
            (ref) async => [
              {
                'status': 'in_progress',
                'checklist_templates': {'name': 'Engine checks'},
                'assets': {'name': 'Harbour tug'},
                'assignee': {'full_name': 'Pat'},
              },
            ],
          ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OrgChecklistAssignmentsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permitted manager sees standalone assignments with one app bar',
    (tester) async {
      await pump(tester, UserRole.clientAdmin);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Assigned checklists'), findsOneWidget);
      expect(find.text('Engine checks'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
    },
  );

  testWidgets('worker cannot render company assignment list', (tester) async {
    await pump(tester, UserRole.clientMechanic);
    expect(
      find.text('You do not have access to team assignments.'),
      findsOneWidget,
    );
    expect(find.text('Engine checks'), findsNothing);
  });

  testWidgets('Spanish assignment view uses localized actions and status', (
    tester,
  ) async {
    await pump(tester, UserRole.client, locale: 'es');
    expect(find.text('Listas asignadas'), findsOneWidget);
    expect(find.text('Abrir biblioteca de listas'), findsOneWidget);
    expect(find.text('En curso'), findsOneWidget);
  });
}
