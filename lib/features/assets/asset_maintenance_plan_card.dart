import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';

class AssetMaintenancePlanCard extends StatelessWidget {
  const AssetMaintenancePlanCard({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.build_outlined),
      title: Text(
        isSpanish(context)
            ? 'Trabajos, componentes y planes'
            : 'Work, components & plans',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/maintenance/assets/$assetId'),
    ),
  );
}
