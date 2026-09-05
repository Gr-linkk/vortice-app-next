import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';

abstract class FleetRepository {
  Future<List<FleetAsset>> fleet();
  Future<List<FleetFault>> faults({String? assetId, String? faultId});
  Future<List<FleetEvent>> faultEvents(String faultId);
  Future<List<FleetEvent>> availabilityEvents(String assetId);
  Future<List<FleetMember>> assignees(String assetId);
  Future<String> report({
    required String requestId,
    required String assetId,
    required String description,
    required bool urgent,
  });
  Future<void> updateFault({
    required FleetFault fault,
    required String operationId,
    required FaultAction action,
    required String note,
    String? assignedTo,
  });
  Future<void> changeAvailability({
    required FleetAsset asset,
    required String operationId,
    required OperatingState state,
    required String reason,
  });
}

class SupabaseFleetRepository implements FleetRepository {
  SupabaseFleetRepository(this._client);
  final SupabaseClient _client;

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  @override
  Future<List<FleetAsset>> fleet() async => _rows(
    await _client.rpc('maintenance_fleet').timeout(const Duration(seconds: 15)),
  ).map(FleetAsset.fromJson).toList();

  @override
  Future<List<FleetFault>> faults({String? assetId, String? faultId}) async =>
      _rows(
        await _client
            .rpc(
              'maintenance_faults',
              params: {
                if (assetId != null) 'p_asset_id': assetId,
                if (faultId != null) 'p_fault_id': faultId,
              },
            )
            .timeout(const Duration(seconds: 15)),
      ).map(FleetFault.fromJson).toList();

  @override
  Future<List<FleetEvent>> faultEvents(String faultId) async => _rows(
    await _client
        .from('maintenance_fault_events')
        .select()
        .eq('fault_id', faultId)
        .order('created_at', ascending: false)
        .order('id')
        .timeout(const Duration(seconds: 15)),
  ).map(FleetEvent.fromJson).toList();

  @override
  Future<List<FleetEvent>> availabilityEvents(String assetId) async => _rows(
    await _client
        .from('asset_availability_events')
        .select()
        .eq('asset_id', assetId)
        .order('created_at', ascending: false)
        .order('id')
        .timeout(const Duration(seconds: 15)),
  ).map(FleetEvent.fromJson).toList();

  @override
  Future<List<FleetMember>> assignees(String assetId) async => _rows(
    await _client
        .rpc('maintenance_assignees', params: {'p_asset_id': assetId})
        .timeout(const Duration(seconds: 15)),
  ).map(FleetMember.fromJson).toList();

  @override
  Future<String> report({
    required String requestId,
    required String assetId,
    required String description,
    required bool urgent,
  }) async =>
      (await _client
              .rpc(
                'report_maintenance_fault',
                params: {
                  'p_request_id': requestId,
                  'p_asset_id': assetId,
                  'p_description': description.trim(),
                  'p_severity': urgent ? 'urgent' : 'normal',
                },
              )
              .timeout(const Duration(seconds: 15)))
          as String;

  @override
  Future<void> updateFault({
    required FleetFault fault,
    required String operationId,
    required FaultAction action,
    required String note,
    String? assignedTo,
  }) async {
    await _client
        .rpc(
          'update_maintenance_fault',
          params: {
            'p_fault_id': fault.id,
            'p_expected_revision': fault.revision,
            'p_operation_id': operationId,
            'p_action': action.value,
            'p_note': note.trim(),
            'p_assigned_to': assignedTo,
          },
        )
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> changeAvailability({
    required FleetAsset asset,
    required String operationId,
    required OperatingState state,
    required String reason,
  }) async {
    await _client
        .rpc(
          'change_asset_availability',
          params: {
            'p_asset_id': asset.id,
            'p_expected_revision': asset.revision,
            'p_operation_id': operationId,
            'p_state': state.value,
            'p_reason': reason.trim(),
          },
        )
        .timeout(const Duration(seconds: 15));
  }
}

String fleetErrorMessage(Object error, bool es) {
  if (error is PostgrestException) {
    if (error.code == '40001' || error.message.contains('already used')) {
      return es
          ? 'Este registro cambió. Cierra el formulario y actualiza antes de guardar.'
          : 'This record changed. Close this form and refresh before saving again.';
    }
    if (error.code == '42501') {
      return es
          ? 'Tu cuenta no tiene permiso para esta acción.'
          : 'Your account does not have permission for this action.';
    }
    if (error.message.contains('urgent')) {
      return es
          ? 'Resuelve o descarta las fallas urgentes antes de marcar Disponible.'
          : 'Resolve or dismiss urgent faults before marking this asset Available.';
    }
    if (error.code == 'PGRST202' || error.code == '42P01') {
      return es
          ? 'Esta función requiere la actualización de Vortice Next.'
          : 'This feature requires the Vortice Next backend update.';
    }
    if (error.code == 'P0001') {
      return es
          ? 'No se pudo aplicar el cambio. Revisa el estado actual y los campos.'
          : error.message;
    }
  }
  return es
      ? 'No se pudo confirmar el guardado o la conexión. Tus datos siguen aquí; reconecta e intenta de nuevo.'
      : 'Could not confirm the connection or save. Your input is kept here; reconnect and retry.';
}
