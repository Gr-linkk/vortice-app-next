import 'checklist_builder_repository.dart';
import 'package:vortice_app/core/list_label_order.dart';
import 'package:vortice_app/core/equipment_art_catalog.dart';

Map<String, dynamic> checklistRowData(Map<String, dynamic> row) =>
    Map<String, dynamic>.from(row['draft'] as Map? ?? row);

/// Group by scope identity, not a guessed name; duplicate asset names stay apart.
String checklistGroupKey(Map<String, dynamic> row) {
  final data = checklistRowData(row);
  final asset = (data['scope_asset_id'] as String?)?.trim();
  final type = (data['asset_type_id'] as String?)?.trim();
  if (asset != null && asset.isNotEmpty) return 'asset:$asset';
  if (type != null && type.isNotEmpty) return 'type:$type';
  return 'general';
}

String checklistGroupLabel(String key, Map<String, dynamic> catalog, bool es) {
  if (key.startsWith('asset:')) {
    final asset = checklistRows(
      catalog['assets'],
    ).where((a) => a['id'] == key.substring(6)).firstOrNull;
    return asset?['name'] as String? ??
        (es ? 'Equipo específico' : 'Specific equipment');
  }
  if (key.startsWith('type:')) {
    final type = checklistRows(
      catalog['asset_types'],
    ).where((a) => a['id'] == key.substring(5)).firstOrNull;
    final art = equipmentArtFor(
      assetTypeId: key.substring(5),
      typeName: type?['name'] as String?,
    );
    if (es && art != EquipmentArt.other) return art.spanishLabel;
    return type?['name'] as String? ??
        (es ? 'Tipo de equipo' : 'Equipment type');
  }
  return es ? 'Listas generales' : 'General checklists';
}

Map<String, List<Map<String, dynamic>>> groupChecklistLibrary(
  List<Map<String, dynamic>> rows,
  Map<String, dynamic> catalog,
  bool es,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    groups.putIfAbsent(checklistGroupKey(row), () => []).add(row);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a == 'general') return b == 'general' ? 0 : 1;
      if (b == 'general') return -1;
      final compared = compareListLabels(
        checklistGroupLabel(a, catalog, es),
        checklistGroupLabel(b, catalog, es),
      );
      return compared == 0 ? a.compareTo(b) : compared;
    });
  return {
    for (final key in keys)
      key: groups[key]!
        ..sort((a, b) {
          final left = checklistRowData(a), right = checklistRowData(b);
          // Keep pre-operation checks together, followed by maintenance procedures.
          final kind = '${left['checklist_type']}'.compareTo(
            '${right['checklist_type']}',
          );
          return kind != 0
              ? kind
              : compareListLabels('${left['name']}', '${right['name']}');
        }),
  };
}
