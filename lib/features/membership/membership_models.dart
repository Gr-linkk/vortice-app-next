import 'package:vortice_app/models/profile.dart';
import 'company_purpose.dart';

enum OrganizationRole {
  companyOwner(
    'company_owner',
    'Company Owner',
    'Propietario de empresa',
    'Propriétaire de l’entreprise',
  ),
  supervisor(
    'supervisor',
    'Supervisor / Manager',
    'Supervisor / Gerente',
    'Superviseur / Gestionnaire',
  ),
  mechanic(
    'mechanic',
    'Mechanic / Technician',
    'Mecánico / Técnico',
    'Mécanicien / Technicien',
  ),
  operator('operator', 'Operator', 'Operador', 'Opérateur');

  const OrganizationRole(this.key, this.en, this.es, this.fr);
  final String key;
  final String en;
  final String es;
  final String fr;
  String label(bool spanish, {bool french = false}) => french
      ? fr
      : spanish
      ? es
      : en;
}

enum OrganizationPermission {
  teamAdmin(
    'team_admin',
    'Manage team',
    'Administrar equipo',
    'Gérer l’équipe',
  ),
  billing('billing', 'Billing', 'Facturación', 'Facturation'),
  inspectionManage(
    'inspection_manage',
    'Manage inspections',
    'Administrar inspecciones',
    'Gérer les inspections',
  ),
  announcementsManage(
    'announcements_manage',
    'Post announcements',
    'Publicar avisos',
    'Publier des annonces',
  );

  const OrganizationPermission(this.key, this.en, this.es, this.fr);
  final String key;
  final String en;
  final String es;
  final String fr;
  String label(bool spanish, {bool french = false}) => french
      ? fr
      : spanish
      ? es
      : en;
}

bool membershipAllows(
  Iterable<String> roles,
  Iterable<String> permissions,
  String permission,
) {
  if (roles.isEmpty) return false;
  if (permission == 'member' ||
      roles.contains('company_owner') ||
      permissions.contains(permission)) {
    return true;
  }
  if (roles.contains('supervisor') &&
      const {
        'assets_manage',
        'planning',
        'assign_work',
        'review_work',
        'approve_work',
      }.contains(permission)) {
    return true;
  }
  if (roles.any(const {'supervisor', 'mechanic'}.contains) &&
      const {
        'work_assigned',
        'reports',
        'labour',
        'parts',
      }.contains(permission)) {
    return true;
  }
  return const {
    'preop',
    'readings',
    'issues',
    'handover',
    'discussions',
  }.contains(permission);
}

extension OrganizationProfileAccess on Profile {
  bool canInOrganization(String permission) =>
      membershipManaged &&
      !onboardingRequired &&
      membershipAllows(organizationRoles, organizationPermissions, permission);
}

class OrganizationMembership {
  const OrganizationMembership({
    required this.organizationId,
    required this.name,
    required this.ownerProfileId,
    required this.roles,
    required this.permissions,
    this.companyPurpose,
    this.providerEnabled = false,
  });
  final String organizationId;
  final String name;
  final String ownerProfileId;
  final List<String> roles;
  final List<String> permissions;
  final CompanyPurpose? companyPurpose;
  final bool providerEnabled;
  bool can(String permission) =>
      membershipAllows(roles, permissions, permission);
  factory OrganizationMembership.fromJson(
    Map<String, dynamic> json,
  ) => OrganizationMembership(
    organizationId: json['organization_id'] as String,
    companyPurpose: CompanyPurpose.parse(json['company_purpose'] as String?),
    providerEnabled: json['provider_enabled'] == true,
    name: json['name'] as String,
    ownerProfileId: json['owner_profile_id'] as String,
    roles: List<String>.from(json['roles'] as List),
    permissions: List<String>.from(json['permissions'] as List? ?? const []),
  );
}

class OrganizationContext {
  const OrganizationContext({
    this.activeOrganizationId,
    this.onboardingRequired = false,
    this.memberships = const [],
  });
  final String? activeOrganizationId;
  final bool onboardingRequired;
  final List<OrganizationMembership> memberships;
  OrganizationMembership? get active {
    for (final membership in memberships) {
      if (membership.organizationId == activeOrganizationId) return membership;
    }
    return null;
  }

  factory OrganizationContext.fromJson(Map<String, dynamic> json) =>
      OrganizationContext(
        activeOrganizationId: json['active_organization_id'] as String?,
        onboardingRequired: json['onboarding_required'] == true,
        memberships: (json['memberships'] as List? ?? const [])
            .map(
              (e) => OrganizationMembership.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
}

class TeamMember {
  const TeamMember({
    required this.profileId,
    required this.name,
    required this.email,
    required this.roles,
    required this.permissions,
    required this.status,
  });
  final String profileId;
  final String name;
  final String email;
  final List<String> roles;
  final List<String> permissions;
  final String status;
  bool get isOwner => roles.contains('company_owner');
  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
    profileId: json['profile_id'] as String,
    name: json['name'] as String,
    email: json['email'] as String? ?? '',
    roles: List<String>.from(json['roles'] as List),
    permissions: List<String>.from(json['permissions'] as List? ?? const []),
    status: json['status'] as String,
  );
}

class MembershipInvitation {
  const MembershipInvitation({
    required this.id,
    required this.roles,
    required this.permissions,
    required this.expiresAt,
    this.contact,
    this.redeemedAt,
    this.revokedAt,
  });
  final String id;
  final List<String> roles;
  final List<String> permissions;
  final DateTime expiresAt;
  final String? contact;
  final DateTime? redeemedAt;
  final DateTime? revokedAt;
  bool activeAt(DateTime now) =>
      redeemedAt == null && revokedAt == null && expiresAt.isAfter(now);
  factory MembershipInvitation.fromJson(Map<String, dynamic> json) =>
      MembershipInvitation(
        id: json['id'] as String,
        roles: List<String>.from(json['roles'] as List),
        permissions: List<String>.from(
          json['permissions'] as List? ?? const [],
        ),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        contact: json['contact'] as String?,
        redeemedAt: DateTime.tryParse(json['redeemed_at'] as String? ?? ''),
        revokedAt: DateTime.tryParse(json['revoked_at'] as String? ?? ''),
      );
}

class OrganizationTeam {
  const OrganizationTeam({
    this.members = const [],
    this.invitations = const [],
  });
  final List<TeamMember> members;
  final List<MembershipInvitation> invitations;
  factory OrganizationTeam.fromJson(Map<String, dynamic> json) =>
      OrganizationTeam(
        members: (json['members'] as List? ?? const [])
            .map(
              (e) => TeamMember.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        invitations: (json['invitations'] as List? ?? const [])
            .map(
              (e) => MembershipInvitation.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
}
