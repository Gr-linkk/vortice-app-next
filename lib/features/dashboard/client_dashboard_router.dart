import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/dashboard/client_dashboard_managed.dart';
import 'package:vortice_app/features/dashboard/client_mechanic_dashboard.dart';
import 'package:vortice_app/features/dashboard/client_operator_dashboard.dart';
import 'package:vortice_app/models/profile.dart';

class ClientDashboardRouter extends ConsumerWidget {
  const ClientDashboardRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final role = profile?.role ?? UserRole.client;

    return switch (role) {
      UserRole.clientMechanic => const ClientMechanicDashboard(),
      UserRole.clientOperator => const ClientOperatorDashboard(), // legacy
      UserRole.operator => const ClientOperatorDashboard(), // merged
      _ => const ClientDashboardManaged(),
    };
  }
}
