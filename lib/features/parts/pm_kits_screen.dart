import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/parts/parts_log_screen.dart';
import 'package:vortice_app/features/parts/pm_kit_card.dart';
import 'package:vortice_app/features/parts/pm_kits_support.dart';
export 'package:vortice_app/features/parts/pm_parts_list_sheet.dart';

// ── Owner Parts Screen (tabs: Parts Log + PM Kits) ───────────────────────────

class OwnerPartsScreen extends StatelessWidget {
  const OwnerPartsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Parts'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt_outlined), text: 'Parts Log'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'PM Kits'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PartsLogScreen(embedded: true),
            PmKitsScreen(),
          ],
        ),
      ),
    );
  }
}

// ── Provider: all clients with their assets and interval-linked PM kits ───────

final pmKitsByClientProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final clients = await supabase
      .from(AppConstants.tProfiles)
      .select('id, full_name, subscription_tier')
      .inFilter('role', ['client', 'client_admin']).order('full_name');

  final result = <Map<String, dynamic>>[];

  for (final client in clients as List) {
    final clientId = client['id'] as String;

    final assets = await supabase
        .from(AppConstants.tAssets)
        .select('id, name, make, model')
        .eq('client_id', clientId)
        .order('name');

    final assetList = <Map<String, dynamic>>[];

    for (final asset in assets as List) {
      final assetId = asset['id'] as String;

      final intervals = await supabase
          .from(AppConstants.tAssetServiceIntervals)
          .select('id, interval_hours, checklist_template_id')
          .eq('asset_id', assetId)
          .not('checklist_template_id', 'is', null)
          .order('interval_hours');

      final kits = <Map<String, dynamic>>[];

      for (final interval in intervals as List) {
        final intervalMap = interval as Map<String, dynamic>;
        final templateId = intervalMap['checklist_template_id'] as String?;
        if (templateId == null) continue;

        final template = await supabase
            .from(AppConstants.tChecklistTemplates)
            .select('id, name, interval_label')
            .eq('id', templateId)
            .maybeSingle();

        final parts = await supabase
            .from(AppConstants.tPmPartsRequirements)
            .select()
            .eq('template_id', templateId)
            .order('description');

        kits.add({
          'interval_id': intervalMap['id'],
          'template_id': templateId,
          'template_name': template?['name'] ?? 'Unknown',
          'interval_label': template?['interval_label'] ??
              '${intervalMap['interval_hours']}HR',
          'interval_hours': intervalMap['interval_hours'],
          'parts': List<Map<String, dynamic>>.from(parts as List),
        });
      }

      if (kits.isNotEmpty) {
        assetList.add({
          'id': assetId,
          'name': asset['name'],
          'make': asset['make'],
          'model': asset['model'],
          'kits': kits,
        });
      }
    }

    if (assetList.isNotEmpty) {
      result.add({
        'id': clientId,
        'name': client['full_name'],
        'tier': client['subscription_tier'],
        'assets': assetList,
      });
    }
  }

  return result;
});

// ── Screen ───────────────────────────────────────────────────────────────────

class PmKitsScreen extends ConsumerWidget {
  const PmKitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kitsAsync = ref.watch(pmKitsByClientProvider);

    return kitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
          child: Text(friendlyError(context, err),
              style: const TextStyle(color: AppColors.error))),
      data: (clients) {
        if (clients.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('No PM kits set up yet.',
                    style: TextStyle(color: AppColors.textSecondary)),
                SizedBox(height: 4),
                Text(
                    'Link checklist templates to service reminders\nto build PM kits per vessel.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pmKitsByClientProvider),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: clients.length,
            itemBuilder: (_, ci) {
              final client = clients[ci];
              final assets = client['assets'] as List<Map<String, dynamic>>;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          client['name'] as String,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  ...assets.map((asset) {
                    final kits = asset['kits'] as List<Map<String, dynamic>>;
                    final makeModel =
                        formatAssetMakeModel(asset['make'] as String?,
                            asset['model'] as String?);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
                          child: Row(
                            children: [
                              const Icon(Icons.directions_boat_outlined,
                                  size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                asset['name'] as String,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                              if (makeModel != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  makeModel,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ...kits.map((kit) => PmKitCard(
                              kit: kit,
                              assetName: asset['name'] as String,
                              onRefresh: () =>
                                  ref.invalidate(pmKitsByClientProvider),
                            )),
                      ],
                    );
                  }),
                  const Divider(height: 1),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
