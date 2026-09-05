import 'package:flutter/material.dart';
import 'package:vortice_app/features/fleet/fleet_screen.dart';

/// Keeps existing asset links while exposing the repair lifecycle.
class MaintenanceFlagsScreen extends StatelessWidget {
  const MaintenanceFlagsScreen({
    super.key,
    required this.assetId,
    required this.assetName,
  });
  final String assetId;
  final String assetName;
  @override
  Widget build(BuildContext context) => FleetScreen(assetId: assetId);
}
