import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_checklists_tab.dart';
import 'package:vortice_app/features/orgs/org_admin_fleet_tab.dart';
import 'package:vortice_app/features/orgs/org_admin_invoices_tab.dart';
import 'package:vortice_app/features/orgs/org_admin_team_tab.dart';
import 'package:vortice_app/models/client_org.dart';

class OrgAdminBody extends ConsumerWidget {
  final ClientOrg org;

  const OrgAdminBody({super.key, required this.org});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4, // Team | Fleet | Checklists | Invoices
      child: Scaffold(
        appBar: AppBar(
          title: Text(org.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Team'),
              Tab(icon: Icon(Icons.directions_boat_outlined), text: 'Fleet'),
              Tab(icon: Icon(Icons.checklist_outlined), text: 'Checklists'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Invoices'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            OrgAdminTeamTab(orgId: org.id, ownerProfileId: org.ownerProfileId),
            OrgAdminFleetTab(ownerProfileId: org.ownerProfileId),
            OrgAdminChecklistsTab(orgId: org.id),
            const OrgAdminInvoicesTab(),
          ],
        ),
      ),
    );
  }
}
