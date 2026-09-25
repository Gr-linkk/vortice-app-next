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
    this.fr = '',
    this.descriptionFr = '',
    this.group = 0,
  });
  final String en, es, route, description, descriptionEs, fr, descriptionFr;
  final IconData icon;
  final int group;
  String label(bool spanish, {bool french = false}) => french && fr.isNotEmpty
      ? fr
      : spanish
      ? es
      : en;
  String detail(bool spanish, {bool french = false}) =>
      french && descriptionFr.isNotEmpty
      ? descriptionFr
      : spanish
      ? descriptionEs
      : description;
}

List<AppDestination> primaryDestinations(
  UserRole role, {
  bool operationalChecklistsEnabled = false,
}) {
  final prefix = roleRoutePrefix(role);
  return [
    AppDestination(
      'Home',
      'Inicio',
      Icons.home_outlined,
      '$prefix/dashboard',
      fr: 'Accueil',
    ),
    const AppDestination(
      'Assets',
      'Equipos',
      Icons.directions_boat_outlined,
      '/assets',
      fr: 'Équipements',
    ),
    if (canUseMaintenance(role))
      const AppDestination(
        'Work orders',
        'Órdenes de trabajo',
        Icons.calendar_month_outlined,
        '/maintenance/planning',
        fr: 'Bons de travail',
      ),
    if ((role == UserRole.operator || role == UserRole.clientOperator) &&
        operationalChecklistsEnabled)
      const AppDestination(
        'Checks',
        'Revisiones',
        Icons.checklist,
        '/operator/checklist',
        fr: 'Inspections',
      ),
    const AppDestination(
      'Faults',
      'Fallas',
      Icons.report_problem_outlined,
      '/fleet',
      fr: 'Défaillances',
    ),
    const AppDestination(
      'More',
      'Más',
      Icons.grid_view_outlined,
      '/more',
      fr: 'Plus',
    ),
  ];
}

List<AppDestination> toolDestinations(UserRole role) {
  final prefix = roleRoutePrefix(role);
  final staff = role == UserRole.owner || role == UserRole.employee;
  final admin = role == UserRole.client || role == UserRole.clientAdmin;
  return [
    if (role == UserRole.owner || admin)
      const AppDestination(
        'Checklist library',
        'Listas de revisión',
        Icons.playlist_add_check,
        '/checklist-library',
        description: 'Build PM procedures and pre-operation checks',
        descriptionEs:
            'Crear procedimientos de mantenimiento y revisiones antes de operar',
        fr: 'Bibliothèque de listes de contrôle',
        descriptionFr:
            'Créer des procédures d’entretien et des inspections avant utilisation',
      ),
    if (role == UserRole.owner || admin)
      const AppDestination(
        'Equipment report',
        'Informe de equipos',
        Icons.bar_chart,
        '/fleet/reporting',
        group: 1,
        description: 'Compare maintenance costs, downtime and repeat faults',
        descriptionEs: 'Comparar costos, inactividad y fallas repetidas',
        fr: 'Rapport sur les équipements',
        descriptionFr:
            'Comparer les coûts d’entretien, les temps d’arrêt et les défaillances récurrentes',
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
        fr: 'Demandes de service',
        descriptionFr: staff
            ? 'Examiner les demandes des clients et organiser les travaux'
            : 'Demander de l’aide et consulter vos demandes précédentes',
      ),
    if (staff || admin || role == UserRole.clientMechanic)
      AppDestination(
        'Service reports',
        'Informes de servicio',
        Icons.description_outlined,
        '$prefix/service-reports',
        description: 'Read completed work and service history',
        descriptionEs: 'Consultar trabajos realizados e historial de servicio',
        fr: 'Rapports d’intervention',
        descriptionFr:
            'Consulter les travaux terminés et l’historique d’entretien',
      ),
    if (staff)
      AppDestination(
        'Parts',
        'Repuestos',
        Icons.inventory_2_outlined,
        '$prefix/parts',
        description: 'Find parts and record materials used',
        descriptionEs: 'Buscar repuestos y registrar materiales utilizados',
        fr: 'Pièces',
        descriptionFr: 'Trouver des pièces et consigner les matériaux utilisés',
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
        fr: 'Factures',
        descriptionFr: 'Consulter les frais et l’état des paiements',
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
        fr: 'Clients',
        descriptionFr:
            'Gérer les comptes clients et les fonctionnalités disponibles',
      ),
      const AppDestination(
        'Invite codes',
        'Códigos de invitación',
        Icons.person_add_outlined,
        '/owner/org-codes',
        group: 1,
        description: 'Help people join the right company',
        descriptionEs: 'Ayudar a las personas a unirse a su empresa',
        fr: 'Codes d’invitation',
        descriptionFr: 'Aider les gens à joindre la bonne entreprise',
      ),
      const AppDestination(
        'Reminders',
        'Recordatorios',
        Icons.event_note_outlined,
        '/owner/reminders',
        description: 'Review upcoming maintenance reminders',
        descriptionEs: 'Revisar recordatorios de mantenimiento',
        fr: 'Rappels',
        descriptionFr: 'Consulter les rappels d’entretien à venir',
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
        fr: 'Équipe',
        descriptionFr: 'Gérer votre entreprise et ses membres',
      ),
    const AppDestination(
      'Notifications',
      'Notificaciones',
      Icons.notifications_outlined,
      '/notifications',
      description: 'Catch up on updates that need attention',
      descriptionEs: 'Consultar novedades que requieren atención',
      fr: 'Notifications',
      descriptionFr: 'Consulter les nouvelles qui demandent votre attention',
    ),
  ];
}

int selectedDestination(List<AppDestination> items, String location) {
  final path = Uri.parse(location).path;
  if (path == '/assets' ||
      path.startsWith('/assets/') ||
      path == '/maintenance/assets' ||
      path.startsWith('/maintenance/assets/')) {
    final assets = items.indexWhere((item) => item.route.endsWith('/assets'));
    if (assets >= 0) return assets;
  }
  if (path.startsWith('/work-orders/') ||
      path == '/maintenance' ||
      path.startsWith('/maintenance/') ||
      path == '/owner/work-orders' ||
      path.startsWith('/owner/work-orders/') ||
      path == '/employee/work-orders' ||
      path.startsWith('/employee/work-orders/')) {
    final work = items.indexWhere(
      (item) => item.route == '/maintenance/planning',
    );
    if (work >= 0) return work;
  }
  for (var i = 0; i < items.length; i++) {
    if (path == items[i].route || path.startsWith('${items[i].route}/')) {
      return i;
    }
  }
  return items.length - 1;
}
