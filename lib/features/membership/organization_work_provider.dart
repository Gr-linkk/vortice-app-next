import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, SupabaseClient;
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'package:vortice_app/sync/field_evidence.dart';

class OrganizationWorkRepository {
  OrganizationWorkRepository({this.queue, SupabaseClient? client})
    : _client = client;
  final FieldWorkQueue? queue;
  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? supabase;
  Future<Map<String, dynamic>> _read(
    String rpc, {
    Map<String, dynamic>? params,
    String? suffix,
  }) async {
    final account = client.auth.currentUser!.id;
    final raw =
        await AccountJsonCache(
          account,
          () => client.auth.currentUser?.id,
        ).readThrough(
          'organization_work:$rpc:${suffix ?? ''}',
          () => client
              .rpc(rpc, params: params)
              .timeout(const Duration(seconds: 8)),
        );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<Map<String, dynamic>> context(String id) => _read(
    'organization_work_order_context',
    params: {'p_work_order': id},
    suffix: id,
  );
  Future<Map<String, dynamic>> configuration() =>
      _read('organization_service_configuration');
  Future<Map<String, dynamic>> requestContext() =>
      _read('organization_service_request_context');
  Future<Map<String, dynamic>> customerCreationContext() =>
      _read('customer_work_creation_context');
  Future<String> createCustomerWork(
    String operation,
    String relationship,
    String asset,
    String title,
    String note, {
    DateTime? serviceDate,
  }) async =>
      await client.rpc(
            'create_customer_work',
            params: {
              'p_operation': operation,
              'p_relationship': relationship,
              'p_asset': asset,
              'p_title': title.trim(),
              'p_note': note.trim(),
              if (serviceDate != null)
                'p_service_date': serviceDate
                    .toIso8601String()
                    .split('T')
                    .first,
            },
          )
          as String;
  Future<void> configure(bool provider, bool billing) async {
    await client.rpc(
      'configure_organization_services',
      params: {'p_provider_enabled': provider, 'p_billing_enabled': billing},
    );
  }

  Future<void> propose(String code) async {
    await client.rpc(
      'propose_organization_customer',
      params: {'p_connection_code': code.trim()},
    );
  }

  Future<void> relationship(
    String provider,
    String customer,
    String action,
  ) async {
    await client.rpc(
      'set_organization_relationship',
      params: {
        'p_provider': provider,
        'p_client': customer,
        'p_action': action,
      },
    );
  }

  Future<String> request(
    String operation,
    String relation,
    String asset,
    String title,
    String note,
  ) async =>
      await client.rpc(
            'request_organization_work',
            params: {
              'p_operation': operation,
              'p_relationship': relation,
              'p_asset': asset,
              'p_title': title.trim(),
              'p_note': note.trim(),
            },
          )
          as String;
  Future<void> change(
    String id,
    int revision,
    String action,
    Map<String, dynamic> data,
  ) => changeOperation(id, revision, const Uuid().v4(), action, data);

  Future<void> changeOperation(
    String id,
    int revision,
    String operation,
    String action,
    Map<String, dynamic> data,
  ) async {
    final account = client.auth.currentUser?.id;
    if (queue != null && (action == 'submit' || action == 'save_report')) {
      await requireUploadedFieldEvidence(
        queue!,
        (data['evidence_paths'] as List? ?? []).cast<String>(),
      );
      queue!.checkAccount();
    }
    if (client.auth.currentUser?.id != account) {
      throw const AccountChangedException();
    }
    await client.rpc(
      'change_organization_work',
      params: {
        'p_work_order': id,
        'p_revision': revision,
        'p_operation': operation,
        'p_action': action,
        'p_data': data,
      },
    );
    if (client.auth.currentUser?.id != account) {
      throw const AccountChangedException();
    }
  }

  Future<String> uploadEvidence(
    String workOrder,
    String account,
    Uint8List bytes,
  ) async {
    if (client.auth.currentUser?.id != account) {
      throw const AccountChangedException();
    }
    final path = '$workOrder/$account/${const Uuid().v4()}.jpg';
    if (queue != null) {
      queue!.checkAccount();
      await queue!.enqueue(fieldEvidenceOperation(path: path, bytes: bytes));
      // Capture returns after durable local storage. Foreground retry uses the
      // existing outbox, even after this editor or the process is closed.
      unawaited(
        queue!.flush().catchError((Object error) {
          // The queue records upload failures. Account changes stop this flush.
        }),
      );
      return path;
    }
    await client.storage
        .from('maintenance-evidence')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    if (client.auth.currentUser?.id != account) {
      throw const AccountChangedException();
    }
    return path;
  }

  Future<Uint8List> evidence(String path) async {
    final account = client.auth.currentUser?.id;
    if (queue != null) {
      final local = await localFieldEvidence(queue!, path);
      if (local != null) return local;
    }
    final bytes = await client.storage
        .from('maintenance-evidence')
        .download(path);
    if (client.auth.currentUser?.id != account) {
      throw const AccountChangedException();
    }
    return bytes;
  }

  Future<void> invoice(
    String id,
    String action,
    Map<String, dynamic> data,
  ) async {
    await client.rpc(
      'organization_invoice_action',
      params: {'p_work_order': id, 'p_action': action, 'p_data': data},
    );
  }
}

final organizationWorkRepositoryProvider = Provider<OrganizationWorkRepository>(
  (ref) => OrganizationWorkRepository(queue: ref.watch(fieldWorkQueueProvider)),
);
final organizationWorkOrderContextProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
      ref.watch(sessionProvider);
      // Resolve membership before starting the scoped read. Watching AsyncValue
      // can invalidate an in-flight .future as membership leaves Loading.
      await ref.watch(organizationContextProvider.future);
      return ref.watch(organizationWorkRepositoryProvider).context(id);
    });
final organizationServiceConfigurationProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
      ref.watch(sessionProvider);
      await ref.watch(organizationContextProvider.future);
      return ref.watch(organizationWorkRepositoryProvider).configuration();
    });
final organizationServiceRequestContextProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
      ref.watch(sessionProvider);
      await ref.watch(organizationContextProvider.future);
      return ref.watch(organizationWorkRepositoryProvider).requestContext();
    });
