import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/engines/engine_screen_body.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class EngineScreen extends ConsumerWidget {
  final String assetId;
  const EngineScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final enginesAsync = ref.watch(enginesForAssetProvider(assetId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.enginesTitle)),
      body: enginesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(friendlyError(context, err)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(enginesForAssetProvider(assetId)),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (engines) => EngineScreenBody(
          assetId: assetId,
          engines: engines,
          onRefresh: () => ref.invalidate(enginesForAssetProvider(assetId)),
          onShowEngineSheet: (ctx, engine) =>
              showEngineFormSheet(ctx, assetId, engine),
          onConfirmDelete: (ctx, engine) =>
              confirmEngineDelete(ctx, ref, l10n, assetId, engine),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showEngineFormSheet(context, assetId, null),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}
