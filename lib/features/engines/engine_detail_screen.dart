import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/engines/engine_form.dart';
import 'package:vortice_app/features/engines/engine_info_row.dart';
import 'package:vortice_app/features/engines/engine_kind_options.dart';
import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/features/hours/hour_log_screen.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/asset_engine.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/assets/asset_workflow_policy.dart';

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
      backgroundColor: context.appColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => EngineForm(assetId: assetId, engine: engine),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canManage = AssetWorkflowPolicy.canManageProfile(
      ref.watch(profileProvider).valueOrNull,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(engine.label),
        actions: [
          if (canManage)
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
            style: TextStyle(
              color: context.appColors.primary,
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
          EngineInfoRow(
            label: 'Meter',
            value: formatMeter(engine.currentHours, engine.meterUnit),
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    HourLogScreen(engineId: engine.id, assetId: assetId),
              ),
            ),
            icon: const Icon(Icons.speed),
            label: const Text('Readings and history'),
          ),
          ref
              .watch(latestEngineHoursProvider(engine.id))
              .when(
                loading: () => const EngineInfoRow(
                  label: 'Latest work-order reading',
                  value: 'Loading…',
                ),
                error: (_, __) => const EngineInfoRow(
                  label: 'Latest work-order reading',
                  value: '—',
                ),
                data: (snapshot) => Column(
                  children: [
                    EngineInfoRow(
                      label: 'Latest work-order reading',
                      value: formatMeter(snapshot.hours, engine.meterUnit),
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
          if (canManage)
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
