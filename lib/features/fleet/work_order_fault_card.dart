import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class WorkOrderFaultCard extends ConsumerWidget {
  const WorkOrderFaultCard({
    super.key,
    required this.workOrderId,
    required this.assetId,
  });
  final String workOrderId, assetId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(fleetFaultsProvider(assetId))
      .when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => FleetError(
          error: error,
          onRetry: () => ref.invalidate(fleetFaultsProvider(assetId)),
        ),
        data: (faults) => Column(
          children: [
            ...faults
                .where((fault) => fault.workOrderId == workOrderId)
                .map(
                  (fault) => Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(
                        fleetText(context, 'Linked fault', 'Falla vinculada'),
                      ),
                      subtitle: Text(
                        fault.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await context.push('/fleet/faults/${fault.id}');
                        if (context.mounted) {
                          refreshFleet(
                            ref,
                            assetId: assetId,
                            faultId: fault.id,
                          );
                        }
                      },
                    ),
                  ),
                ),
          ],
        ),
      );
}
