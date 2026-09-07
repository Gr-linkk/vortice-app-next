import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/asset_icons.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart' as sb;
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/models/asset.dart';

final assetsByClientProvider = FutureProvider.family<List<Asset>, String>((
  ref,
  clientId,
) async {
  final data = await sb.supabase
      .from(AppConstants.tAssets)
      .select()
      .eq('client_id', clientId)
      .order('name');
  return (data as List)
      .map((e) => Asset.fromJson(e as Map<String, dynamic>))
      .toList();
});

class ClientAssetsSection extends ConsumerWidget {
  final String clientId;

  const ClientAssetsSection({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(assetsByClientProvider(clientId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vessels & Equipment',
          style: TextStyle(
            color: context.appColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        assetsAsync.when(
          loading: () => const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => Text(
            'Could not load assets',
            style: TextStyle(color: context.appColors.error, fontSize: 12),
          ),
          data: (assets) {
            if (assets.isEmpty) {
              return Text(
                'No assets assigned',
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 13,
                ),
              );
            }
            return Column(
              children: assets
                  .map(
                    (asset) => InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/owner/assets/${asset.id}');
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: context.appColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: context.appColors.cardBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              assetIconFor(asset.assetTypeId),
                              size: 18,
                              color: context.appColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    asset.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: context.appColors.textPrimary,
                                    ),
                                  ),
                                  if (asset.make != null || asset.model != null)
                                    Text(
                                      [
                                        asset.make,
                                        asset.model,
                                      ].whereType<String>().join(' · '),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.appColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: context.appColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
