import 'package:flutter/material.dart';
import 'package:vortice_app/features/fleet/fault_report_screen.dart';

/// Existing operator entry point now uses the tracked report workflow.
class MaintenanceFlagScreen extends StatelessWidget {
  const MaintenanceFlagScreen({super.key});
  @override
  Widget build(BuildContext context) => const FaultReportScreen();
}
