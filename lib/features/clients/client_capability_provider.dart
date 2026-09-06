import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/client_capability.dart';

final clientCapabilitiesRepositoryProvider =
    Provider<ClientCapabilitiesRepository>((ref) {
      return ClientCapabilitiesRepository();
    });

final clientCapabilitiesProvider =
    FutureProvider.family<ClientCapabilitySwitchboard, String>((ref, clientId) {
      final repository = ref.watch(clientCapabilitiesRepositoryProvider);
      ref.watch(sessionProvider);
      return repository.fetchForClient(clientId);
    });

class ClientCapabilitiesRepository {
  Future<ClientCapabilitySwitchboard> fetchForClient(String clientId) async {
    final account = supabase.auth.currentUser?.id;
    if (account == null) {
      return ClientCapabilitySwitchboard(
        clientId: clientId,
        enabledByCapability: const {},
      );
    }
    final data =
        await AccountJsonCache(
          account,
          () => supabase.auth.currentUser?.id,
        ).readThrough(
          'capabilities:$clientId',
          () => supabase
              .from(AppConstants.tClientCapabilities)
              .select('capability_key, enabled')
              .eq('client_id', clientId)
              .timeout(const Duration(seconds: 6)),
        );

    final enabledByCapability = <ClientCapability, bool>{
      for (final capability in ClientCapability.values) capability: false,
    };

    for (final row in data as List) {
      final json = row as Map<String, dynamic>;
      final capability = ClientCapability.tryFromKey(
        json['capability_key'] as String,
      );
      if (capability == null) continue;
      enabledByCapability[capability] = json['enabled'] as bool? ?? false;
    }

    return ClientCapabilitySwitchboard(
      clientId: clientId,
      enabledByCapability: enabledByCapability,
    );
  }

  Future<void> setCapability({
    required String clientId,
    required ClientCapability capability,
    required bool enabled,
  }) async {
    await supabase.from(AppConstants.tClientCapabilities).upsert({
      'client_id': clientId,
      'capability_key': capability.key,
      'enabled': enabled,
      'updated_by': supabase.auth.currentUser?.id,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'client_id,capability_key');
  }
}

class ClientCapabilityController extends StateNotifier<AsyncValue<void>> {
  ClientCapabilityController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<bool> setCapability({
    required String clientId,
    required ClientCapability capability,
    required bool enabled,
  }) async {
    state = const AsyncLoading();
    var success = false;
    state = await AsyncValue.guard(() async {
      final repository = _ref.read(clientCapabilitiesRepositoryProvider);
      await repository.setCapability(
        clientId: clientId,
        capability: capability,
        enabled: enabled,
      );
      _ref.invalidate(clientCapabilitiesProvider(clientId));
      success = true;
    });
    return success;
  }
}

final clientCapabilityControllerProvider =
    StateNotifierProvider<ClientCapabilityController, AsyncValue<void>>((ref) {
      return ClientCapabilityController(ref);
    });
