import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_form.dart';
import 'package:vortice_app/features/engines/engine_info_row.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/features/engines/engine_screen_support.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset_engine.dart';

class EngineDetailScreen extends ConsumerWidget {
  final String assetId;
  final AssetEngine engine;

  const EngineDetailScreen({
    super.key,
    required this.assetId,
    required this.engine,
  });

  void _showEditSheet(BuildContext context) {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(engine.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: l10n.edit,
            onPressed: () => _showEditSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            engineKindLabel(engine.kind),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 16),
          EngineInfoRow(label: 'Label', value: engine.label),
          EngineInfoRow(label: 'Manufacturer', value: engine.make),
          EngineInfoRow(label: 'Model', value: engine.model),
          EngineInfoRow(label: 'Serial Number', value: engine.serialNumber),
          ref.watch(latestEngineHoursProvider(engine.id)).when(
                loading: () => const EngineInfoRow(
                  label: 'Latest Work Order Hours',
                  value: 'Loading…',
                ),
                error: (_, __) => const EngineInfoRow(
                  label: 'Latest Work Order Hours',
                  value: '—',
                ),
                data: (snapshot) => Column(
                  children: [
                    EngineInfoRow(
                      label: 'Latest Work Order Hours',
                      value: formatLatestEngineHoursDetail(snapshot.hours),
                    ),
                    if (snapshot.title != null)
                      EngineInfoRow(
                        label: 'Source Work Order',
                        value: snapshot.title,
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _showEditSheet(context),
            child: Text(l10n.edit),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
