import 'package:vortice_app/core/user_feedback.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/clients/client_capability_gate.dart';
import 'package:vortice_app/features/engines/engine_provider.dart';
import 'package:vortice_app/features/telemetry/telemetry_provider.dart';
import 'package:vortice_app/features/telemetry/vessel_telemetry_body.dart';
import 'package:vortice_app/models/asset_engine.dart';
import 'package:vortice_app/models/client_capability.dart';

/// Live telemetry view for a single vessel / asset.
/// Polling interval: 30 seconds.
class VesselTelemetryScreen extends ConsumerStatefulWidget {
  final String assetId;

  const VesselTelemetryScreen({super.key, required this.assetId});

  @override
  ConsumerState<VesselTelemetryScreen> createState() =>
      _VesselTelemetryScreenState();
}

class _VesselTelemetryScreenState extends ConsumerState<VesselTelemetryScreen> {
  Timer? _pollingTimer;
  AssetEngine? _selectedEngine;

  @override
  void initState() {
    super.initState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(latestTelemetryForAssetProvider(widget.assetId));
      ref.invalidate(alertsForAssetProvider(widget.assetId));
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _refreshTelemetry() {
    ref.invalidate(latestTelemetryForAssetProvider(widget.assetId));
    ref.invalidate(alertsForAssetProvider(widget.assetId));
  }

  @override
  Widget build(BuildContext context) {
    final assetAsync = ref.watch(assetByIdProvider(widget.assetId));
    final enginesAsync = ref.watch(enginesForAssetProvider(widget.assetId));

    return assetAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Vessel Telemetry')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Vessel Telemetry')),
        body: Center(
          child: Text(friendlyError(context, err),
              style: const TextStyle(color: AppColors.error)),
        ),
      ),
      data: (asset) {
        if (asset == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vessel Telemetry')),
            body: const Center(child: Text('Asset not found.')),
          );
        }

        return ClientCapabilityGate(
          clientId: asset.clientId,
          capability: ClientCapability.telemetry,
          blockedBuilder: (_) => Scaffold(
            appBar: AppBar(title: Text(asset.name)),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: ClientCapabilityDisabledPanel(
                  capability: ClientCapability.telemetry,
                ),
              ),
            ),
          ),
          allowedBuilder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(asset.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: _refreshTelemetry,
                ),
              ],
            ),
            body: VesselTelemetryBody(
              asset: asset,
              enginesAsync: enginesAsync,
              selectedEngine: _selectedEngine,
              onEngineSelected: (e) => setState(() => _selectedEngine = e),
            ),
          ),
        );
      },
    );
  }
}
