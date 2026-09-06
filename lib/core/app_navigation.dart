import 'package:flutter/material.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';

String roleRoutePrefix(UserRole role) => switch (role) {
  UserRole.owner => '/owner',
  UserRole.employee => '/employee',
  _ => '/client',
};

class AppDestination {
  const AppDestination(
    this.en,
    this.es,
    this.icon,
    this.route, {
    this.description = '',
    this.descriptionEs = '',
    this.group = 0,
  });
  final String en, es, route, description, descriptionEs;
  final IconData icon;
  final int group;
  String label(bool spanish) => spanish ? es : en;
  String detail(bool spanish) => spanish ? descriptionEs : description;
}

List<AppDestination> primaryDestinations(
  UserRole role, {
  bool operationalChecklistsEnabled = false,
}) {
  final prefix = roleRoutePrefix(role);
  return [
    AppDestination('Home', 'Inicio', Icons.home_outlined, '$prefix/dashboard'),
    AppDestination(
      'Assets',
      'Equipos',
      Icons.directions_boat_outlined,
      '$prefix/assets',
    ),
    if (canUseMaintenance(role))
      const AppDestination(
        'Work',
        'Trabajo',
        Icons.build_outlined,
        '/maintenance',
      ),
    if ((role == UserRole.operator || role == UserRole.clientOperator) &&
        operationalChecklistsEnabled)
      const AppDestination(
        'Checks',
        'Revisiones',
        Icons.checklist,
        '/operator/checklist',
      ),
    const AppDestination(
      'Faults',
      'Fallas',
      Icons.report_problem_outlined,
      '/fleet',
    ),
    const AppDestination('More', 'Más', Icons.grid_view_outlined, '/more'),
  ];
}

List<AppDestination> toolDestinations(UserRole role) {
  final prefix = roleRoutePrefix(role);
  final staff = role == UserRole.owner || role == UserRole.employee;
  final admin = role == UserRole.client || role == UserRole.clientAdmin;
  return [
    const AppDestination(
      'Fleet inspections',
      'Inspecciones de la flota',
      Icons.fact_check_outlined,
      '/assurance',
      description: 'Track custody, inspection evidence and expiry dates',
      descriptionEs: 'Consultar custodia, evidencia y vencimientos',
    ),
    if (role == UserRole.owner || admin)
      const AppDestination(
        'Fleet decisions',
        'Decisiones de la flota',
        Icons.dashboard_outlined,
        '/fleet/overview',
        description: 'Act on overdue service, faults and waiting work',
        descriptionEs: 'Atender servicios vencidos, fallas y trabajo pendiente',
      ),
    if (canUseMaintenance(role))
      const AppDestination(
        'Assets & plans',
        'Equipos y planes',
        Icons.event_note_outlined,
        '/maintenance/assets',
        description: 'Manage components and schedule reliable maintenance',
        descriptionEs: 'Administrar componentes y programar mantenimiento',
      ),
    if (staff)
      AppDestination(
        'Service work orders',
        'Órdenes de servicio',
        Icons.build_outlined,
        '$prefix/work-orders',
        description: 'Existing provider jobs and customer billing workflows',
        descriptionEs: 'Trabajos del proveedor y facturación al cliente',
      ),
    if (staff || admin)
      AppDestination(
        'Service requests',
        'Solicitudes de servicio',
        Icons.support_agent,
        '$prefix/service-requests',
        description: staff
            ? 'Review customer requests and arrange work'
            : 'Request help and follow your previous requests',
        descriptionEs: staff
            ? 'Revisar solicitudes y organizar el trabajo'
            : 'Pedir ayuda y consultar solicitudes anteriores',
      ),
    if (staff || admin || role == UserRole.clientMechanic)
      AppDestination(
        'Service reports',
        'Informes de servicio',
        Icons.description_outlined,
        '$prefix/service-reports',
        description: 'Read completed work and service history',
        descriptionEs: 'Consultar trabajos realizados e historial de servicio',
      ),
    if (staff)
      AppDestination(
        'Parts',
        'Repuestos',
        Icons.inventory_2_outlined,
        '$prefix/parts',
        description: 'Find parts and record materials used',
        descriptionEs: 'Buscar repuestos y registrar materiales utilizados',
      ),
    if (role == UserRole.owner || admin)
      AppDestination(
        'Invoices',
        'Facturas',
        Icons.receipt_long_outlined,
        '$prefix/invoices',
        group: 1,
        description: 'View charges and payment status',
        descriptionEs: 'Consultar cargos y estado de pago',
      ),
    if (role == UserRole.owner) ...[
      const AppDestination(
        'Clients',
        'Clientes',
        Icons.business_outlined,
        '/owner/clients',
        group: 1,
        description: 'Manage customer accounts and capabilities',
        descriptionEs: 'Administrar clientes y funciones disponibles',
      ),
      const AppDestination(
        'Invite codes',
        'Códigos de invitación',
        Icons.person_add_outlined,
        '/owner/org-codes',
        group: 1,
        description: 'Help people join the right company',
        descriptionEs: 'Ayudar a las personas a unirse a su empresa',
      ),
      const AppDestination(
        'Reminders',
        'Recordatorios',
        Icons.event_note_outlined,
        '/owner/reminders',
        description: 'Review upcoming maintenance reminders',
        descriptionEs: 'Revisar recordatorios de mantenimiento',
      ),
    ],
    if (admin)
      const AppDestination(
        'Team',
        'Equipo de trabajo',
        Icons.groups_outlined,
        '/org/admin',
        group: 1,
        description: 'Manage your company and its members',
        descriptionEs: 'Administrar tu empresa y sus miembros',
      ),
    const AppDestination(
      'Notifications',
      'Notificaciones',
      Icons.notifications_outlined,
      '/notifications',
      description: 'Catch up on updates that need attention',
      descriptionEs: 'Consultar novedades que requieren atención',
    ),
  ];
}

int selectedDestination(List<AppDestination> items, String location) {
  final path = Uri.parse(location).path;
  for (var i = 0; i < items.length; i++) {
    if (path == items[i].route || path.startsWith('${items[i].route}/')) {
      return i;
    }
  }
  return items.length - 1;
}
