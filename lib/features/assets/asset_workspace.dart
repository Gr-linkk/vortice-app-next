import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/coordination/coordination_repository.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';

final assetWorkspaceProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final actor = await ref.watch(profileProvider.future);
    if (actor == null) {
      return {'items': <Map<String, dynamic>>[], 'counts': <String, dynamic>{}};
    }
    final items = await AccountJsonCache(actor.id, () => supabase.auth.currentUser?.id)
        .readThrough('asset_workspace:items', () async {
          final result = await supabase
              .rpc('asset_workspace', params: {'p_today': localCalendarDate()})
              .timeout(const Duration(seconds: 6));
          return (result as Map)['items'] ?? [];
        });
    if (supabase.auth.currentUser?.id != actor.id) {
      throw StateError('Account changed. Reopen Assets.');
    }
    return {'items': items};
  },
);

const assetWorkspaceFilters = <String, (String, String)>{
  'all': ('All assets', 'Todos los equipos'),
  'attention': ('Needs attention', 'Necesita atención'),
  'unavailable': ('Unavailable', 'No disponible'),
  'unassessed': ('Availability unknown', 'Disponibilidad desconocida'),
  'overdue_service': ('Service due', 'Servicio pendiente'),
  'approaching_service': ('Service approaching', 'Servicio próximo'),
  'inspection_expired': ('Expired inspections', 'Inspecciones vencidas'),
  'inspection_upcoming': (
    'Inspections due in 30 days',
    'Inspecciones en 30 días',
  ),
  'inspection_pending': ('Inspection review', 'Revisión de inspección'),
  'inspection_unverified': (
    'Unverified inspections',
    'Inspecciones sin verificar',
  ),
  'plan_setup': ('Maintenance setup', 'Configurar mantenimiento'),
};

bool assetMatchesWorkspaceFilter(Map<String, dynamic> row, String filter) {
  final categories = (row['categories'] as List? ?? []).cast<String>().toSet();
  return switch (filter) {
    'all' => true,
    'attention' =>
      categories.intersection(assetWorkspaceFilters.keys.toSet()).isNotEmpty,
    _ => categories.contains(filter),
  };
}

List<Map<String, dynamic>> filterWorkspaceAssets(
  Map<String, dynamic> page,
  String filter,
) => maintenanceRows(
  page['items'],
).where((row) => assetMatchesWorkspaceFilter(row, filter)).toList();

String assetWorkspaceDestination(String filter) =>
    '/assets?filter=${Uri.encodeQueryComponent(filter)}';

List<String> topWorkspacePriorities(Map<String, dynamic> page) => [
  for (final key in [
    'unavailable',
    'inspection_expired',
    'inspection_pending',
    'overdue_service',
    'plan_setup',
  ])
    if (filterWorkspaceAssets(page, key).isNotEmpty) key,
].take(3).toList();
