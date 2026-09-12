import 'package:flutter/material.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/orgs/org_admin_team_tab.dart';
import 'package:vortice_app/models/client_org.dart';

class OrgAdminBody extends StatelessWidget {
  final ClientOrg org;

  const OrgAdminBody({super.key, required this.org});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSpanish(context) ? 'Equipo · ${org.name}' : 'Team · ${org.name}',
        ),
      ),
      body: OrgAdminTeamTab(orgId: org.id, ownerProfileId: org.ownerProfileId),
    );
  }
}
