import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_detail_screen.dart';
import 'package:vortice_app/features/engines/engine_form.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/engines/engine_tile.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset_engine.dart';

class EngineScreenBody extends ConsumerWidget {
  final String assetId;
  final List<AssetEngine> engines;
  final VoidCallback onRefresh;
  final void Function(BuildContext context, AssetEngine? engine) onShowEngineSheet;
  final void Function(BuildContext context, AssetEngine engine) onConfirmDelete;

  const EngineScreenBody({
    super.key,
    required this.assetId,
    required this.engines,
    required this.onRefresh,
    required this.onShowEngineSheet,
    required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (engines.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return Center(
        child: Text(l10n.noEngines,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: engines.length,
        itemBuilder: (_, i) => EngineTile(
          engine: engines[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EngineDetailScreen(
                assetId: assetId,
                engine: engines[i],
              ),
            ),
          ),
          onEdit: () => onShowEngineSheet(context, engines[i]),
          onDelete: () => onConfirmDelete(context, engines[i]),
        ),
      ),
    );
  }
}

void showEngineFormSheet(
  BuildContext context,
  String assetId,
  AssetEngine? engine,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => EngineForm(
      assetId: assetId,
      engine: engine,
    ),
  );
}

Future<void> confirmEngineDelete(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  String assetId,
  AssetEngine engine,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(l10n.confirmDelete),
      content: Text(l10n.confirmDeleteMessage),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => ctx.pop(true),
          child: Text(l10n.delete,
              style: const TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref
        .read(engineControllerProvider.notifier)
        .deleteEngine(engine.id, assetId);
  }
}
