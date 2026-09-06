import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';

abstract class MaintenanceRepository {
  Future<List<MaintenanceJob>> jobs({String? jobId, String? assetId});
  Future<Map<String, dynamic>> workspace();
  Future<Map<String, dynamic>> assetContext(String assetId);
  Future<String> create(String operationId, Map<String, dynamic> data);
  Future<void> change(
    String jobId,
    int revision,
    String operationId,
    String action,
    Map<String, dynamic> data,
  );
  Future<String> setup(
    String operationId,
    String kind,
    String id,
    int revision,
    Map<String, dynamic> data,
  );
  Future<void> uploadEvidence(String path, Uint8List bytes, String contentType);
  Future<String> evidenceUrl(String path);
}

class SupabaseMaintenanceRepository implements MaintenanceRepository {
  SupabaseMaintenanceRepository(this.client);
  final SupabaseClient client;
  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) =>
      client.rpc(name, params: params).timeout(const Duration(seconds: 20));
  @override
  Future<List<MaintenanceJob>> jobs({String? jobId, String? assetId}) async =>
      maintenanceRows(
        await _rpc('maintenance_jobs', {
          if (jobId != null) 'p_job': jobId,
          if (assetId != null) 'p_asset': assetId,
        }),
      ).map(MaintenanceJob.new).toList();
  @override
  Future<Map<String, dynamic>> workspace() async =>
      Map<String, dynamic>.from(await _rpc('maintenance_workspace') as Map);
  @override
  Future<Map<String, dynamic>> assetContext(String assetId) async =>
      Map<String, dynamic>.from(
        await _rpc('maintenance_asset_context', {'p_asset': assetId}) as Map,
      );
  @override
  Future<String> create(String operationId, Map<String, dynamic> data) async =>
      await _rpc('create_maintenance_job', {
            'p_request': operationId,
            'p_data': data,
          })
          as String;
  @override
  Future<void> change(
    String jobId,
    int revision,
    String operationId,
    String action,
    Map<String, dynamic> data,
  ) async {
    await _rpc('change_maintenance_job', {
      'p_job': jobId,
      'p_revision': revision,
      'p_operation': operationId,
      'p_action': action,
      'p_data': data,
    });
  }

  @override
  Future<String> setup(
    String operationId,
    String kind,
    String id,
    int revision,
    Map<String, dynamic> data,
  ) async =>
      await _rpc('save_maintenance_setup', {
            'p_operation': operationId,
            'p_kind': kind,
            'p_id': id,
            'p_revision': revision,
            'p_data': data,
          })
          as String;
  @override
  Future<void> uploadEvidence(
    String path,
    Uint8List bytes,
    String contentType,
  ) async {
    try {
      await client.storage
          .from('maintenance-evidence')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          )
          .timeout(const Duration(seconds: 30));
    } on StorageException catch (error) {
      // The same immutable file/path is retried after an uncertain response.
      if (error.statusCode != '409') rethrow;
      await evidenceUrl(path);
    }
  }

  @override
  Future<String> evidenceUrl(String path) =>
      client.storage.from('maintenance-evidence').createSignedUrl(path, 300);
}

/// Freeze the payload before the first request. A network retry sends the exact
/// same operation and content, even if the original response was lost.
class MaintenanceWrite {
  MaintenanceWrite(Map<String, dynamic> data, {String? operationId})
    : id = operationId ?? const Uuid().v4(),
      data = Map<String, dynamic>.unmodifiable(
        jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
      );
  final String id;
  final Map<String, dynamic> data;
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => SupabaseMaintenanceRepository(supabase),
);
final maintenanceJobsProvider = FutureProvider.autoDispose
    .family<List<MaintenanceJob>, String?>((ref, assetId) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      return ref.watch(maintenanceRepositoryProvider).jobs(assetId: assetId);
    });
final maintenanceJobProvider = FutureProvider.autoDispose
    .family<MaintenanceJob?, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return null;
      return (await ref.watch(maintenanceRepositoryProvider).jobs(jobId: id))
          .firstOrNull;
    });
final maintenanceWorkspaceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      if (await ref.watch(profileProvider.future) == null) return {};
      return ref.watch(maintenanceRepositoryProvider).workspace();
    });
final maintenanceAssetProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return {};
      return ref.watch(maintenanceRepositoryProvider).assetContext(id);
    });

bool maintenanceWriteWasRejected(Object error) =>
    error is PostgrestException &&
    [
      'P0001',
      '40001',
      '42501',
      '23505',
      '23514',
      '22P02',
      '22003',
    ].contains(error.code);
String maintenanceError(Object error, bool es) {
  if (error is PostgrestException) {
    if (error.code == '40001') {
      return es
          ? 'El registro cambió. Actualiza antes de editar.'
          : 'This record changed. Refresh before editing.';
    }
    if (error.code == '23505') {
      return es
          ? 'Ya hay una sesión de trabajo activa. Pausa esa sesión primero.'
          : 'A labour session is already running. Pause it first.';
    }
    if (error.code == 'P0001' && !es) return error.message;
    if (maintenanceWriteWasRejected(error)) {
      return es
          ? 'No se guardó. Revisa los campos, permisos y estado del trabajo.'
          : 'Not saved. Check the fields, permissions and job status.';
    }
    if (error.code == 'PGRST202') {
      return es
          ? 'Esta función necesita la actualización del servicio.'
          : 'This feature needs the maintenance backend update.';
    }
  }
  return es
      ? 'No se pudo confirmar. Conservamos tus datos; vuelve a intentar el mismo guardado.'
      : 'Could not confirm the save. Your input is kept; retry the same save.';
}
