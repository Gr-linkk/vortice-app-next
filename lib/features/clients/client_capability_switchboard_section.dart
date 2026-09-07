import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/clients/client_screen_support.dart';
import 'package:vortice_app/models/client_capability.dart';

class ClientCapabilitySwitchboardSection extends ConsumerWidget {
  final String clientId;

  const ClientCapabilitySwitchboardSection({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final switchboardAsync = ref.watch(clientCapabilitiesProvider(clientId));
    final controllerState = ref.watch(clientCapabilityControllerProvider);
    final isSaving = controllerState is AsyncLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Service Switchboard',
          style: TextStyle(
            color: context.appColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Controls access to new workflow areas. Turning a switch off hides the workflow; existing records are preserved.',
          style: TextStyle(
            color: context.appColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: clientAlwaysOnCapabilities.map((label) {
            return Chip(
              avatar: const Icon(Icons.lock_open, size: 14),
              label: Text(label),
              backgroundColor: context.appColors.surfaceVariant,
              side: BorderSide(color: context.appColors.cardBorder),
              labelStyle: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 12,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        switchboardAsync.when(
          loading: () => const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => Row(
            children: [
              Expanded(
                child: Text(
                  'Could not load service switches',
                  style: TextStyle(
                    color: context.appColors.error,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(clientCapabilitiesProvider(clientId)),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (switchboard) => Column(
            children: ClientCapability.values.map((capability) {
              final enabled = switchboard.isEnabled(capability);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: context.appColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.appColors.cardBorder),
                ),
                child: SwitchListTile.adaptive(
                  value: enabled,
                  onChanged: isSaving
                      ? null
                      : (value) async {
                          final success = await ref
                              .read(clientCapabilityControllerProvider.notifier)
                              .setCapability(
                                clientId: clientId,
                                capability: capability,
                                enabled: value,
                              );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? '${capability.label} ${value ? 'enabled' : 'disabled'}.'
                                    : 'Could not update ${capability.label}.',
                              ),
                            ),
                          );
                        },
                  title: Text(
                    capability.label,
                    style: TextStyle(
                      color: context.appColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    capability.description,
                    style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  dense: true,
                  activeThumbColor: context.appColors.primary,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
