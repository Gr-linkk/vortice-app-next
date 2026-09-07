import 'package:flutter/material.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/asset.dart';

class ServiceIntervalAssetHeader extends StatelessWidget {
  final Asset? asset;

  const ServiceIntervalAssetHeader({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    if (asset == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_boat_outlined,
            color: context.appColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset!.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (asset!.make != null || asset!.model != null)
                  Text(
                    [asset!.make, asset!.model].whereType<String>().join(' '),
                    style: TextStyle(
                      color: context.appColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
