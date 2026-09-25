import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/localized_text.dart';

class AssetMaintenancePlanCard extends StatelessWidget {
  const AssetMaintenancePlanCard({super.key, required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.build_outlined),
      title: Text(
        localizedText(
          context,
          'Work, components & plans',
          'Trabajos, componentes y planes',
          'Travaux, composants et plans',
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/maintenance/assets/$assetId'),
    ),
  );
}
