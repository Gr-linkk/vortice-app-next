import 'package:vortice_app/core/app_retry_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/engines/engine_screen_body.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';

class EngineScreen extends ConsumerWidget {
  final String assetId;
  const EngineScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canManage = AssetWorkflowPolicy.canManageProfile(
      ref.watch(profileProvider).valueOrNull,
    );
    final enginesAsync = ref.watch(enginesForAssetProvider(assetId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.enginesTitle)),
      body: enginesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => AppRetryPanel(
          error: err,
          onRetry: () => ref.invalidate(enginesForAssetProvider(assetId)),
        ),
        data: (engines) => EngineScreenBody(
          canManage: canManage,
          assetId: assetId,
          engines: engines,
          onRefresh: () => ref.invalidate(enginesForAssetProvider(assetId)),
          onShowEngineSheet: (ctx, engine) =>
              showEngineFormSheet(ctx, assetId, engine),
          onConfirmDelete: (ctx, engine) =>
              confirmEngineDelete(ctx, ref, l10n, assetId, engine),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => showEngineFormSheet(context, assetId, null),
              backgroundColor: context.appColors.primary,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
