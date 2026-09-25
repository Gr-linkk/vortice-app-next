/// Older frozen snapshots omit each item's template ID. Carry the saved parent
/// publication into the read model so procedure links can request their exact
/// source page. Explicit item identities and stored snapshots remain unchanged.
List<Map<String, dynamic>> checklistSnapshotItems(
  dynamic rows,
  String? templateId,
) => [
  for (final raw in (rows as List? ?? const []).whereType<Map>())
    {
      ...Map<String, dynamic>.from(raw),
      if (raw['template_id'] == null && templateId != null)
        'template_id': templateId,
    },
];
