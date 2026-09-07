import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'agent_mfa.dart';

abstract class AgentAccessRepository {
  bool get ownerVerified;
  Future<Map<String, dynamic>> prepareOwnerVerification();
  Future<void> verifyOwner(String factor, String code);
  Future<Map<String, dynamic>> load();
  Future<Map<String, dynamic>> create(String fleet, String name, bool drafts);
  Future<void> revoke({String? connection, String? fleet, bool all = false});
}

class SupabaseAgentAccessRepository implements AgentAccessRepository {
  SupabaseAgentAccessRepository(this.client, this.actorId);
  final SupabaseClient client;
  final String actorId;
  AgentMfa get _mfa => AgentMfa(client, actorId);
  @override
  bool get ownerVerified => _mfa.verified;
  @override
  Future<Map<String, dynamic>> prepareOwnerVerification() => _mfa.prepare();
  @override
  Future<void> verifyOwner(String factor, String code) =>
      _mfa.verify(factor, code);

  Future<dynamic> _call(String name, [Map<String, dynamic>? params]) async {
    if (client.auth.currentUser?.id != actorId) {
      throw StateError('Account changed');
    }
    final result = await client
        .rpc(name, params: params)
        .timeout(const Duration(seconds: 20));
    if (client.auth.currentUser?.id != actorId) {
      throw StateError('Account changed');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> load() async =>
      Map<String, dynamic>.from(await _call('agent_access_context') as Map);

  @override
  Future<Map<String, dynamic>> create(
    String fleet,
    String name,
    bool drafts,
  ) async => Map<String, dynamic>.from(
    await _call('create_agent_connection', {
          'p_client': fleet,
          'p_label': name,
          'p_allow_drafts': drafts,
        })
        as Map,
  );

  @override
  Future<void> revoke({
    String? connection,
    String? fleet,
    bool all = false,
  }) async {
    await _call('revoke_agent_connections', {
      'p_connection': connection,
      'p_client': fleet,
      'p_all': all,
    });
  }
}

final agentAccessRepositoryProvider = Provider<AgentAccessRepository>((ref) {
  final actor = ref.watch(sessionProvider)?.user.id ?? '';
  return SupabaseAgentAccessRepository(supabase, actor);
});
