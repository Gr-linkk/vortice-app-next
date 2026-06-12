import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/features/clients/client_screen_support.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';

class ClientListTile extends ConsumerWidget {
  final Profile client;

  const ClientListTile({super.key, required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assetCount = ref.watch(clientAssetCountProvider(client.id));
    final woCount = ref.watch(clientWorkOrderCountProvider(client.id));

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(Icons.person, color: AppColors.primary, size: 22),
        ),
        title: Text(client.fullName,
            style: Theme.of(context).textTheme.titleSmall),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(client.email,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            Row(
              children: [
                Text(
                  '${assetCount.valueOrNull ?? 0} ${l10n.navAssets}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 12),
                Text(
                  '${woCount.valueOrNull ?? 0} ${l10n.navWorkOrders}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () => showClientDetailSheet(context, client),
        isThreeLine: true,
      ),
    );
  }
}
