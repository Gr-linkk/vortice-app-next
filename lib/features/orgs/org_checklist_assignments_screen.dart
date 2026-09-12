import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_checklists_tab.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/models/profile.dart';

/// Existing company assignment view, reached from the Checklist library.
/// Checklist authoring still uses the library's live capability checks.
class OrgChecklistAssignmentsScreen extends ConsumerWidget {
  const OrgChecklistAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(es ? 'Listas asignadas' : 'Assigned checklists'),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorState(
          error: error,
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (person) {
          if (person == null ||
              ![UserRole.client, UserRole.clientAdmin].contains(person.role)) {
            return Center(
              child: Text(
                es
                    ? 'No tienes acceso a las asignaciones del equipo.'
                    : 'You do not have access to team assignments.',
              ),
            );
          }
          return ref
              .watch(currentUserOrgProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => AppErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(currentUserOrgProvider),
                ),
                data: (org) => org == null
                    ? Center(
                        child: Text(
                          es
                              ? 'No se encontró un equipo.'
                              : 'No team workspace found.',
                        ),
                      )
                    : OrgAdminChecklistsTab(orgId: org.id),
              );
        },
      ),
    );
  }
}
