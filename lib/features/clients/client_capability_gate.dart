import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/clients/client_context_provider.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/models/profile.dart';

typedef ClientCapabilityGateRequest = ({
  String? clientId,
  ClientCapability capability,
});

/// Product-behavior gate for optional client service capabilities.
///
/// Owner/employee users bypass capability switches so Vórtice can always manage
/// setup, history, and service records. Client-side users require the capability
/// to be enabled for their client.
final clientCapabilityGateProvider =
    FutureProvider.family<bool, ClientCapabilityGateRequest>(
        (ref, request) async {
  final profile = await ref.watch(profileProvider.future);

  if (_isVorticeStaff(profile)) return true;

  final clientId = request.clientId?.isNotEmpty == true
      ? request.clientId!
      : await ref.watch(currentClientIdProvider.future);
  if (clientId == null || clientId.isEmpty) return false;

  final switchboard =
      await ref.watch(clientCapabilitiesProvider(clientId).future);
  return switchboard.isEnabled(request.capability);
});

bool _isVorticeStaff(Profile? profile) =>
    profile != null && isVorticeStaffRole(profile.role);

class ClientCapabilityGate extends ConsumerWidget {
  const ClientCapabilityGate({
    super.key,
    required this.clientId,
    required this.capability,
    required this.allowedBuilder,
    required this.blockedBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String? clientId;
  final ClientCapability capability;
  final WidgetBuilder allowedBuilder;
  final WidgetBuilder blockedBuilder;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowedAsync = ref.watch(clientCapabilityGateProvider((
      clientId: clientId,
      capability: capability,
    )));

    return allowedAsync.when(
      loading: () =>
          loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator()),
      error: (err, _) =>
          errorBuilder?.call(context, err) ??
          Center(
            child: Text(friendlyError(context, err),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
      data: (allowed) =>
          allowed ? allowedBuilder(context) : blockedBuilder(context),
    );
  }
}

class ClientCapabilityDisabledPanel extends StatelessWidget {
  const ClientCapabilityDisabledPanel({
    super.key,
    required this.capability,
    this.message,
  });

  final ClientCapability capability;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ?? '${capability.label} is not enabled for this client.',
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
