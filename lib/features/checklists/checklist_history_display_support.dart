bool looksLikeProfileId(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  final trimmed = value.trim();
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(trimmed);
}

String formatChecklistCompletedByDisplay({
  String? completedByName,
  String? completedBy,
  String? submittedByName,
  String? submittedBy,
}) {
  for (final candidate in [
    completedByName,
    if (!looksLikeProfileId(completedBy)) completedBy,
    submittedByName,
    if (!looksLikeProfileId(submittedBy)) submittedBy,
  ]) {
    final trimmed = candidate?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return '—';
}

String formatChecklistSubmittedByRole(String? role) {
  if (role == null || role.trim().isEmpty) return '—';
  return role
      .trim()
      .split('_')
      .map((part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
