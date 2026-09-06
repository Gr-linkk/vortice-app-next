import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';

abstract class AssuranceRepository {
  Future<Map<String, dynamic>> context(String asset);
  Future<List<Map<String, dynamic>>> inspections(String? asset);
  Future<void> write(
    String action,
    String target,
    int revision,
    String operation,
    Map<String, dynamic> data,
  );
  Future<void> upload(String path, Uint8List bytes, String type);
  Future<String> imageUrl(String path);
  Future<void> discard(String path);
}

class SupabaseAssuranceRepository implements AssuranceRepository {
  SupabaseAssuranceRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> context(String asset) async =>
      Map<String, dynamic>.from(
        await client
                .rpc('asset_assurance_context', params: {'p_asset': asset})
                .timeout(const Duration(seconds: 20))
            as Map,
      );
  @override
  Future<List<Map<String, dynamic>>> inspections(String? asset) async =>
      maintenanceRows(
        await client
            .rpc('inspection_register', params: {'p_asset': asset})
            .timeout(const Duration(seconds: 20)),
      );
  @override
  Future<void> write(
    String action,
    String target,
    int revision,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final name = switch (action) {
      'transfer' => 'transfer_asset_custody',
      'create' => 'create_asset_inspection',
      _ => 'change_asset_inspection',
    };
    await client
        .rpc(
          name,
          params: {
            if (action == 'transfer' || action == 'create')
              'p_asset': target
            else
              'p_inspection': target,
            if (action != 'create') 'p_revision': revision,
            if (action != 'create' && action != 'transfer') 'p_action': action,
            'p_operation': operation,
            'p_data': data,
          },
        )
        .timeout(const Duration(seconds: 20));
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String type) async {
    try {
      await client.storage
          .from('inspection-evidence')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: type),
          )
          .timeout(const Duration(seconds: 30));
    } on StorageException catch (error) {
      if (error.statusCode != '409') rethrow;
      await imageUrl(path);
    }
  }

  @override
  Future<String> imageUrl(String path) =>
      client.storage.from('inspection-evidence').createSignedUrl(path, 300);
  @override
  Future<void> discard(String path) async {
    // RLS only permits removing this uploader's unsubmitted evidence.
    await client.storage.from('inspection-evidence').remove([path]);
  }
}

final assuranceRepositoryProvider = Provider<AssuranceRepository>(
  (ref) => SupabaseAssuranceRepository(supabase),
);
final assuranceContextProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, asset) async {
      if (await ref.watch(profileProvider.future) == null) return {};
      return ref.watch(assuranceRepositoryProvider).context(asset);
    });
final inspectionRegisterProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, asset) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      return ref.watch(assuranceRepositoryProvider).inspections(asset);
    });
final inspectionImageProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) async {
      if (await ref.watch(profileProvider.future) == null) {
        throw StateError('Sign in');
      }
      return ref.watch(assuranceRepositoryProvider).imageUrl(path);
    });

String inspectionState(Map<String, dynamic> item, DateTime now) {
  final approved = item['approved'] as Map?;
  if (approved == null) return 'unverified';
  final expiry = DateTime.parse(approved['expires_on'] as String);
  final today = DateTime(now.year, now.month, now.day);
  if (expiry.isBefore(today)) return 'expired';
  if (!expiry.isAfter(DateTime(today.year, today.month, today.day + 30))) {
    return 'upcoming';
  }
  return 'current';
}

String assuranceLabel(String key, bool es) => switch (key) {
  'active' => es ? 'Activo' : 'Active',
  'stored' => es ? 'Almacenado' : 'Stored',
  'retired' => es ? 'Retirado' : 'Retired',
  'pending' => es ? 'Pendiente de revisión' : 'Awaiting review',
  'approved' => es ? 'Aprobado' : 'Approved',
  'returned' => es ? 'Devuelto para cambios' : 'Returned for changes',
  'unverified' => es ? 'Sin aprobación' : 'Unverified',
  'expired' => es ? 'Vencido' : 'Expired',
  'upcoming' => es ? 'Vence en 30 días' : 'Due within 30 days',
  'current' => es ? 'Vigente' : 'Current',
  _ => key,
};
