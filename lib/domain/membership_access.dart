/// Company capabilities, independent of login, route names and storage.
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
