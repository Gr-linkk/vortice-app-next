import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

class OperatorDashboard extends ConsumerWidget {
  const OperatorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetsAsync = ref.watch(operatorAssignedAssetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.operatorDashboardTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(operatorAssignedAssetsProvider),
        child: assetsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(err.toString(),
                style: const TextStyle(color: AppColors.error)),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_boat_outlined,
                        size: 48, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    Text(l10n.noAssets,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              );
            }

            // Group by client name
            final grouped = <String, List<Map<String, dynamic>>>{};
            for (final row in rows) {
              final clientName =
                  (row['profiles'] as Map<String, dynamic>?)?['full_name']
                          as String? ??
                      'Unknown Client';
              grouped.putIfAbsent(clientName, () => []).add(row);
            }

            final sortedClients = grouped.keys.toList()..sort();

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: sortedClients.length,
              itemBuilder: (context, i) {
                final clientName = sortedClients[i];
                final assets = grouped[clientName]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Client header
                    Container(
                      width: double.infinity,
                      color: AppColors.surfaceVariant,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              color: AppColors.textSecondary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            clientName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${assets.length}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Assets for this client
                    ...assets.map((row) => _AssetTile(
                          assetId: row['id'] as String,
                          assetName: row['name'] as String,
                          make: row['make'] as String?,
                          location: row['location'] as String?,
                        )),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final String assetId;
  final String assetName;
  final String? make;
  final String? location;

  const _AssetTile({
    required this.assetId,
    required this.assetName,
    this.make,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.surfaceVariant,
          child: Icon(Icons.directions_boat, color: AppColors.primary, size: 20),
        ),
        title: Text(assetName),
        subtitle: Text(
          [make, location].whereType<String>().join(' · '),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: const Icon(Icons.checklist_rtl,
            color: AppColors.primary, size: 20),
        onTap: () => context.go('/operator/checklist?assetId=$assetId'),
      ),
    );
  }
}
