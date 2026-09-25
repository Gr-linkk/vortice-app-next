import 'dart:convert';
import 'dart:typed_data';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_evidence.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'maintenance_models.dart';
part 'maintenance_field_projection.dart';

abstract class MaintenanceRepository {
  Future<List<MaintenanceJob>> jobs({String? jobId, String? assetId});
  Future<Map<String, dynamic>> workspace();
  Future<Map<String, dynamic>> assetContext(String assetId);
  Future<String> create(String operationId, Map<String, dynamic> data);
  Future<String> planFault(
    String faultId,
    int revision,
    String operationId,
    Map<String, dynamic> data,
  );
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
  SupabaseMaintenanceRepository(this.client, {this.cache, this.queue});
  final SupabaseClient client;
  final AccountJsonCache? cache;
  final FieldWorkQueue? queue;
  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) =>
      client.rpc(name, params: params).timeout(const Duration(seconds: 6));
  Future<dynamic> _read(String name, [Map<String, dynamic>? params]) =>
      cache?.readThrough(
        '$name:${jsonEncode(params)}',
        () => _rpc(name, params),
      ) ??
      _rpc(name, params);
  @override
  Future<List<MaintenanceJob>> jobs({String? jobId, String? assetId}) async {
    final params = {
      if (jobId != null) 'p_job': jobId,
      if (assetId != null) 'p_asset': assetId,
    };
    final rows = maintenanceRows(
      cache == null
          ? await _rpc('maintenance_jobs', params)
          : await cache!.readThrough(
              'maintenance_jobs:${jsonEncode(params)}',
              () => _rpc('maintenance_jobs', params),
              derivedValues: (data) => {
                for (final row in maintenanceRows(data))
                  'maintenance_jobs:${jsonEncode({'p_job': row['id']})}': [row],
              },
              replaceDerivedPrefix: jobId == null && assetId == null
                  ? 'maintenance_jobs:{"p_job":'
                  : null,
            ),
    );
    final operations = await queue?.list() ?? [];
    return rows
        .map((row) => projectMaintenanceFieldWork(row, operations))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> workspace() async =>
      Map<String, dynamic>.from(await _read('maintenance_workspace') as Map);
  @override
  Future<Map<String, dynamic>> assetContext(String assetId) async =>
      Map<String, dynamic>.from(
        await _read('maintenance_asset_context', {'p_asset': assetId}) as Map,
      );
  @override
  Future<String> create(String operationId, Map<String, dynamic> data) async =>
      await _rpc('create_maintenance_job', {
            'p_request': operationId,
            'p_data': data,
          })
          as String;
  @override
  Future<String> planFault(
    String faultId,
    int revision,
    String operationId,
    Map<String, dynamic> data,
  ) async =>
      await _rpc('plan_fault_work_order', {
            'p_fault': faultId,
            'p_revision': revision,
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
    if (queue != null &&
        [
          'start',
          'pause',
          'block',
          'save_report',
          'submit',
          'add_part',
          'remove_part',
        ].contains(action)) {
      await queue!.restoreEvidence(
        (data['evidence_paths'] as List? ?? []).cast<String>(),
      );
      final previous = (await queue!.list())
          .where((r) => r.id == operationId)
          .firstOrNull;
      final operation =
          previous ??
          FieldOperation(
            id: operationId,
            kind: 'apply_maintenance_field_action',
            subject: jobId,
            payload: {
              'p_job': jobId,
              'p_revision': revision,
              'p_operation': operationId,
              'p_action': action,
              'p_data': {...data, '_actor': queue!.account},
              'p_recorded_at': DateTime.now().toUtc().toIso8601String(),
            },
          );
      await queue!.submit(operation);
      return;
    }
    if (queue != null &&
        (await queue!.list()).any(
          (o) => o.subject == jobId && !o.synced && o.status != 'cancelled',
        )) {
      throw const PostgrestException(
        message:
            'Sync or resolve pending field changes before managing this job.',
        code: 'P0001',
      );
    }
    if (action == 'edit_details') {
      await _rpc('update_internal_work_order', {
        'p_job': jobId,
        'p_revision': revision,
        'p_operation': operationId,
        'p_data': data,
      });
      return;
    }
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
    if (queue != null) {
      await queue!.submit(
        fieldEvidenceOperation(
          path: path,
          bytes: bytes,
          contentType: contentType,
        ),
      );
      return;
    }
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

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  final account = ref.watch(sessionProvider)?.user.id;
  return SupabaseMaintenanceRepository(
    supabase,
    cache: account == null
        ? null
        : AccountJsonCache(account, () => supabase.auth.currentUser?.id),
    queue: ref.watch(fieldWorkQueueProvider),
  );
});
final maintenanceJobsProvider = FutureProvider.autoDispose
    .family<List<MaintenanceJob>, String?>((ref, assetId) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      ref.watch(fieldOperationsProvider);
      return ref.watch(maintenanceRepositoryProvider).jobs(assetId: assetId);
    });
final maintenanceJobProvider = FutureProvider.autoDispose
    .family<MaintenanceJob?, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return null;
      ref.watch(fieldOperationsProvider);
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
String maintenanceError(Object error, bool es, {bool french = false}) {
  if (error is PostgrestException) {
    if (error.code == '40001') {
      return french
          ? 'Cet enregistrement a changé. Actualisez-le avant de le modifier.'
          : es
          ? 'El registro cambió. Actualiza antes de editar.'
          : 'This record changed. Refresh before editing.';
    }
    if (error.code == '23505') {
      return french
          ? 'Une session de travail est déjà en cours. Mettez-la en pause d’abord.'
          : es
          ? 'Ya hay una sesión de trabajo activa. Pausa esa sesión primero.'
          : 'A labour session is already running. Pause it first.';
    }
    if (error.code == 'P0001' && !es && !french) return error.message;
    if (maintenanceWriteWasRejected(error)) {
      return french
          ? 'Enregistrement impossible. Vérifiez les champs, les autorisations et l’état du bon de travail.'
          : es
          ? 'No se guardó. Revisa los campos, permisos y estado del trabajo.'
          : 'Not saved. Check the fields, permissions and job status.';
    }
    if (error.code == 'PGRST202') {
      return french
          ? 'Cette fonction nécessite la mise à jour du service d’entretien.'
          : es
          ? 'Esta función necesita la actualización del servicio.'
          : 'This feature needs the maintenance backend update.';
    }
  }
  return french
      ? 'Impossible de confirmer l’enregistrement. Vos données sont conservées; réessayez le même enregistrement.'
      : es
      ? 'No se pudo confirmar. Conservamos tus datos; vuelve a intentar el mismo guardado.'
      : 'Could not confirm the save. Your input is kept; retry the same save.';
}
