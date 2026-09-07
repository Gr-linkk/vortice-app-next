import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import '../maintenance_models.dart';
import '../maintenance_repository.dart';
import 'planning_models.dart';
import 'planning_repository.dart';
import 'schedule_job_screen.dart';

class MaintenancePlanningScreen extends ConsumerStatefulWidget {
  const MaintenancePlanningScreen({super.key, this.assetId, this.jobId});
  final String? assetId, jobId;
  @override
  ConsumerState<MaintenancePlanningScreen> createState() =>
      _MaintenancePlanningScreenState();
}

class _MaintenancePlanningScreenState
    extends ConsumerState<MaintenancePlanningScreen> {
  DateTime _day = planningDay(DateTime.now());
  String? _view, _asset, _person;
  String _query = '', _planFilter = 'all';
  String? _openedJobId;

  @override
  void didUpdateWidget(covariant MaintenancePlanningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId ||
        oldWidget.assetId != widget.assetId) {
      _openedJobId = null;
      ref.invalidate(maintenancePlanningProvider(widget.assetId));
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(workOrdersProvider);
    ref.invalidate(maintenancePlanningProvider(widget.assetId));
    await ref.read(maintenancePlanningProvider(widget.assetId).future);
  }

  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) ref.invalidate(maintenancePlanningProvider);
  }

  Future<void> _schedule(PlanningJob job, List<PlanningJob> jobs) async {
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ScheduleJobScreen(job: job, jobs: jobs),
      ),
    );
    if (mounted) ref.invalidate(maintenancePlanningProvider);
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final manager = isMaintenanceManager(profile?.role);
    final view = _view ?? (manager ? 'week' : 'today');
    if (!canUseMaintenance(profile?.role)) {
      return Scaffold(
        appBar: AppBar(title: Text(es ? 'Planificación' : 'Planning')),
        body: Center(
          child: Text(
            es
                ? 'Tu perfil no tiene acceso.'
                : 'Your role does not have access.',
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          manager
              ? (es ? 'Planificación' : 'Maintenance planning')
              : (es ? 'Mi programación' : 'My schedule'),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: es ? 'Actualizar' : 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: es ? 'Más opciones' : 'More options',
            onSelected: (value) => _open(value),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: widget.assetId == null
                    ? '/maintenance/assets'
                    : '/maintenance/assets/${widget.assetId}',
                child: Text(es ? 'Equipos y planes' : 'Assets & plans'),
              ),
            ],
          ),
        ],
      ),
      body: ref
          .watch(maintenancePlanningProvider(widget.assetId))
          .when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      es
                          ? 'No se pudo cargar la planificación actual. Conéctate y vuelve a intentar.'
                          : 'Could not load the current plan. Connect and try again.',
                    ),
                    const SizedBox(height: 12),
                    Text(maintenanceError(error, es)),
                    TextButton(
                      onPressed: _refresh,
                      child: Text(es ? 'Reintentar' : 'Try again'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/maintenance'),
                      child: Text(
                        es ? 'Abrir trabajo guardado' : 'Open saved work',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            data: (data) {
              if (_openedJobId != widget.jobId && widget.jobId != null) {
                final job = data.jobs
                    .where((j) => j.id == widget.jobId)
                    .firstOrNull;
                if (job != null && job.schedulable) {
                  _openedJobId = widget.jobId;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _schedule(job, data.jobs);
                  });
                }
              }
              final assets = <String, String>{
                for (final job in data.jobs) job.assetId: job.assetName,
                for (final plan in data.plans) plan.assetId: plan.assetName,
              };
              final people = <String, String>{
                for (final job in data.jobs)
                  if (job.assignee != null) job.assignee!: job.assigneeName,
              };
              final selectedAsset = assets.containsKey(_asset) ? _asset : null;
              final selectedPerson = people.containsKey(_person)
                  ? _person
                  : null;
              final jobs =
                  data.jobs
                      .where(
                        (j) =>
                            (selectedAsset == null ||
                                j.assetId == selectedAsset) &&
                            (selectedPerson == null ||
                                j.assignee == selectedPerson) &&
                            '${j.title} ${j.assetName} ${j.assigneeName}'
                                .toLowerCase()
                                .contains(_query),
                      )
                      .toList()
                    ..sort(comparePlanningJobs);
              final plans =
                  data.plans
                      .where(
                        (p) =>
                            (selectedAsset == null ||
                                p.assetId == selectedAsset) &&
                            '${p.title} ${p.assetName} ${p.component ?? ''}'
                                .toLowerCase()
                                .contains(_query),
                      )
                      .toList()
                    ..sort((a, b) {
                      final first = (a.hasJob ? 1 : 0).compareTo(
                        b.hasJob ? 1 : 0,
                      );
                      return first != 0
                          ? first
                          : (a.remainingHours ?? double.infinity).compareTo(
                              b.remainingHours ?? double.infinity,
                            );
                    });
              final today = planningDay(DateTime.now());
              final week = planningWeek(_day);
              final until = DateTime(week.year, week.month, week.day + 7);
              final displayed = jobs
                  .where(
                    (j) => switch (view) {
                      'today' || 'month' => j.inPeriod(
                        _day,
                        DateTime(_day.year, _day.month, _day.day + 1),
                      ),
                      'week' => j.inPeriod(week, until),
                      'unscheduled' => j.unscheduled,
                      'attention' =>
                        j.overdue(today) ||
                            j.conflict ||
                            j.status == 'on_hold' ||
                            j.status == 'pending_review',
                      _ => false,
                    },
                  )
                  .toList();
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    Text(
                      manager
                          ? (es
                                ? 'Próximos servicios y trabajo del equipo'
                                : 'Upcoming services and team work')
                          : (es
                                ? 'Tu trabajo programado, listo para continuar.'
                                : 'Your scheduled work, ready to continue.'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (manager)
                          FilledButton.icon(
                            onPressed: () => context.push(
                              Uri(
                                path: '/maintenance/new',
                                queryParameters: {
                                  'planning': 'true',
                                  if (widget.assetId ?? selectedAsset
                                      case final String id)
                                    'assetId': id,
                                },
                              ).toString(),
                            ),
                            icon: const Icon(Icons.add),
                            label: Text(
                              es ? 'Planificar trabajo' : 'Plan work',
                            ),
                          ),
                        TextButton(
                          onPressed: () => _open(
                            '/maintenance${widget.assetId == null ? '' : '?assetId=${widget.assetId}'}',
                          ),
                          child: Text(es ? 'Todo el trabajo' : 'All work'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (jobs.any((j) => j.overdue(today) || j.unscheduled) ||
                        plans.any((p) => p.due && !p.hasJob))
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            label: Text(
                              '${jobs.where((j) => j.overdue(today)).length} ${es ? 'vencidos' : 'overdue'}',
                            ),
                            onPressed: () =>
                                setState(() => _view = 'attention'),
                          ),
                          ActionChip(
                            label: Text(
                              '${jobs.where((j) => j.unscheduled).length} ${es ? 'sin programar' : 'unscheduled'}',
                            ),
                            onPressed: () =>
                                setState(() => _view = 'unscheduled'),
                          ),
                          if (manager)
                            ActionChip(
                              label: Text(
                                '${plans.where((p) => p.due && !p.hasJob).length} ${es ? 'servicios pendientes' : 'services due'}',
                              ),
                              onPressed: () => setState(() {
                                _view = 'plans';
                                _planFilter = 'due';
                              }),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      maintainState: true,
                      title: Text(es ? 'Buscar y filtrar' : 'Search & filters'),
                      subtitle:
                          _query.isNotEmpty ||
                              selectedAsset != null ||
                              selectedPerson != null
                          ? Text(es ? 'Filtros activos' : 'Filters active')
                          : null,
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            labelText: es
                                ? 'Buscar trabajo o servicio'
                                : 'Search work or service',
                            prefixIcon: const Icon(Icons.search),
                          ),
                          onChanged: (value) => setState(
                            () => _query = value.toLowerCase().trim(),
                          ),
                        ),
                        if (widget.assetId == null && assets.length > 1) ...[
                          const SizedBox(height: 16),
                          AppDropdownField<String>(
                            key: ValueKey('asset-$selectedAsset'),
                            initialValue: selectedAsset ?? '',
                            decoration: InputDecoration(
                              labelText: es ? 'Equipo' : 'Asset',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  es ? 'Todos los equipos' : 'All assets',
                                ),
                              ),
                              for (final asset in assets.entries)
                                DropdownMenuItem(
                                  value: asset.key,
                                  child: Text(asset.value),
                                ),
                            ],
                            onChanged: (value) => setState(
                              () => _asset = value == '' ? null : value,
                            ),
                          ),
                        ],
                        if (manager &&
                            people.isNotEmpty &&
                            view != 'plans') ...[
                          const SizedBox(height: 16),
                          AppDropdownField<String>(
                            key: ValueKey('person-$selectedPerson'),
                            initialValue: selectedPerson ?? '',
                            decoration: InputDecoration(
                              labelText: es ? 'Responsable' : 'Assignee',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  es ? 'Todo el equipo' : 'Whole team',
                                ),
                              ),
                              for (final person in people.entries)
                                DropdownMenuItem(
                                  value: person.key,
                                  child: Text(person.value),
                                ),
                            ],
                            onChanged: (value) => setState(
                              () => _person = value == '' ? null : value,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final option in [
                          ('today', es ? 'Día' : 'Day'),
                          ('week', es ? 'Semana' : 'Week'),
                          ('month', es ? 'Mes' : 'Month'),
                          ('unscheduled', es ? 'Sin programar' : 'Unscheduled'),
                          ('attention', es ? 'Por atender' : 'Needs attention'),
                          if (manager)
                            (
                              'plans',
                              es ? 'Planes de servicio' : 'Service plans',
                            ),
                        ])
                          ChoiceChip(
                            label: Text(option.$2),
                            selected: view == option.$1,
                            onSelected: (_) =>
                                setState(() => _view = option.$1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (['today', 'week', 'month'].contains(view)) ...[
                      Row(
                        children: [
                          IconButton(
                            tooltip: es ? 'Anterior' : 'Previous',
                            onPressed: () => setState(
                              () => _day = view == 'month'
                                  ? DateTime(_day.year, _day.month - 1, 1)
                                  : DateTime(
                                      _day.year,
                                      _day.month,
                                      _day.day - (view == 'week' ? 7 : 1),
                                    ),
                            ),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              view == 'week'
                                  ? '${DateFormat.MMMd(es ? 'es' : 'en').format(week)} – ${DateFormat.yMMMd(es ? 'es' : 'en').format(DateTime(week.year, week.month, week.day + 6))}'
                                  : view == 'month'
                                  ? DateFormat.yMMMM(
                                      es ? 'es' : 'en',
                                    ).format(_day)
                                  : DateFormat.yMMMd(
                                      es ? 'es' : 'en',
                                    ).format(_day),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: es ? 'Siguiente' : 'Next',
                            onPressed: () => setState(
                              () => _day = view == 'month'
                                  ? DateTime(_day.year, _day.month + 1, 1)
                                  : DateTime(
                                      _day.year,
                                      _day.month,
                                      _day.day + (view == 'week' ? 7 : 1),
                                    ),
                            ),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () => setState(() => _day = today),
                          child: Text(es ? 'Hoy' : 'Today'),
                        ),
                      ),
                      if (view == 'month')
                        PlanningMonth(
                          day: _day,
                          jobs: jobs,
                          es: es,
                          onSelect: (date) => setState(() => _day = date),
                        ),
                      if (view == 'week' && manager && displayed.isNotEmpty)
                        Card(
                          child: ExpansionTile(
                            title: Text(
                              '${es ? 'Reservas del equipo' : 'Team bookings'} · ${displayed.fold<double>(0, (sum, j) => sum + j.hoursBetween(week, until)).toStringAsFixed(1)} h',
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              for (final person in {
                                for (final job in displayed) job.assignee ?? '',
                              })
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    '${person.isEmpty ? (es ? 'Sin asignar' : 'Unassigned') : people[person]} · ${displayed.where((j) => (j.assignee ?? '') == person).fold<double>(0, (sum, j) => sum + j.hoursBetween(week, until)).toStringAsFixed(1)} h',
                                  ),
                                ),
                              Text(
                                es
                                    ? 'Son estimaciones, no disponibilidad confirmada. Las órdenes de servicio sin hora no suman horas.'
                                    : 'Estimates, not confirmed availability. Untimed service orders add no booked hours.',
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (view == 'plans') ...[
                      Text(
                        es
                            ? 'Los intervalos existentes siguen definiendo qué servicio corresponde. Programa su ejecución con antelación.'
                            : 'Existing intervals still define which service is due. Book its execution ahead of time.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final option in [
                            ('all', es ? 'Todos' : 'All'),
                            ('due', es ? 'Pendientes' : 'Due'),
                            (
                              'setup',
                              es ? 'Revisar configuración' : 'Needs setup',
                            ),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              selected: _planFilter == option.$1,
                              onSelected: (_) =>
                                  setState(() => _planFilter = option.$1),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (final plan in plans.where(
                        (p) => _planFilter == 'due'
                            ? p.due && !p.hasJob
                            : _planFilter == 'setup'
                            ? p.needsSetup
                            : true,
                      ))
                        _planCard(plan, es),
                      if (plans
                          .where(
                            (p) => _planFilter == 'due'
                                ? p.due && !p.hasJob
                                : _planFilter == 'setup'
                                ? p.needsSetup
                                : true,
                          )
                          .isEmpty)
                        _empty(
                          es
                              ? 'No hay planes con este filtro. Abre Equipos y planes para configurar los servicios.'
                              : 'No plans match this view. Open Assets & plans to set up services.',
                        ),
                    ] else ...[
                      if (displayed.isEmpty)
                        _empty(
                          view == 'unscheduled'
                              ? (es
                                    ? 'No hay trabajo sin programar.'
                                    : 'No unscheduled work.')
                              : (es
                                    ? 'No hay trabajo con este filtro.'
                                    : 'No work in this view.'),
                        ),
                      for (final job in displayed) _jobCard(job, data.jobs, es),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      es
                          ? 'Planificación en línea · Horarios locales del dispositivo'
                          : 'Online planning · Times local to this device',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(message),
  );

  Widget _jobCard(PlanningJob job, List<PlanningJob> jobs, bool es) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (job.providerService)
            Text(
              es
                  ? 'Orden de servicio · sin hora reservada'
                  : 'Service order · no time booked',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          if (job.serviceDate != null)
            Text(DateFormat.yMMMd(es ? 'es' : 'en').format(job.serviceDate!)),
          if (job.start != null)
            Text(
              '${DateFormat.MMMEd(es ? 'es' : 'en').add_Hm().format(job.start!)} · ${(job.minutes / 60).toStringAsFixed(1)} h',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          const SizedBox(height: 4),
          Text(job.title, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${job.assetName}${job.data['component_name'] == null ? '' : ' · ${job.data['component_name']}'}',
          ),
          Text(
            '${job.assigneeName.isEmpty ? (es ? 'Sin asignar' : 'Unassigned') : job.assigneeName} · ${maintenanceStatus(job.status, es)} · ${maintenancePriority(job.priority, es)}',
          ),
          if (job.dueDate != null)
            Text(
              '${es ? 'Fecha límite' : 'Deadline'}: ${maintenanceDate(job.dueDate, es)}',
              style: job.overdue(DateTime.now())
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          if (job.conflict)
            Text(
              es
                  ? 'Conflicto de horario: revisa el responsable y el equipo.'
                  : 'Schedule overlap: review the assignee and asset.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (job.status == 'on_hold')
            Text(
              '${es ? 'Bloqueado' : 'Blocked'}: ${job.data['on_hold_reason'] ?? ''}',
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (job.schedulable)
                FilledButton(
                  onPressed: () => _schedule(job, jobs),
                  child: Text(
                    job.start == null
                        ? (es ? 'Programar' : 'Schedule')
                        : (es ? 'Reprogramar' : 'Reschedule'),
                  ),
                ),
              TextButton(
                onPressed: () => _open(job.route),
                child: Text(
                  job.providerService
                      ? (es ? 'Abrir orden de servicio' : 'Open service order')
                      : job.schedulable
                      ? (es ? 'Abrir trabajo' : 'Open work')
                      : (es ? 'Continuar trabajo' : 'Continue work'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _planCard(PlanningPlan plan, bool es) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan.title, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${plan.assetName} · ${plan.component ?? (es ? 'Sin componente' : 'No component')}',
          ),
          Text(
            plan.needsSetup
                ? (es
                      ? 'Vincula un componente y revisa la línea base.'
                      : 'Link a component and review the service baseline.')
                : plan.due
                ? '${es ? 'Servicio pendiente' : 'Service due'} · ${plan.remainingHours!.abs().toStringAsFixed(0)} h ${es ? 'desde el vencimiento' : 'past threshold'}'
                : '${plan.remainingHours!.toStringAsFixed(0)} h ${es ? 'hasta el próximo servicio' : 'until next service'}',
          ),
          if (plan.hasJob)
            Text(es ? 'Ya tiene trabajo abierto.' : 'Already has open work.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (plan.openJobId != null)
                FilledButton(
                  onPressed: () => _open('/maintenance/jobs/${plan.openJobId}'),
                  child: Text(
                    es ? 'Abrir trabajo planificado' : 'Open planned work',
                  ),
                )
              else if (!plan.hasJob && !plan.needsSetup && plan.canManage)
                FilledButton(
                  onPressed: () => context.push(
                    '/maintenance/new?assetId=${plan.assetId}&planId=${plan.id}&planning=true',
                  ),
                  child: Text(es ? 'Planificar servicio' : 'Plan service'),
                ),
              TextButton(
                onPressed: () => _open('/maintenance/assets/${plan.assetId}'),
                child: Text(es ? 'Revisar plan' : 'Review plan'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class PlanningMonth extends StatelessWidget {
  const PlanningMonth({
    super.key,
    required this.day,
    required this.jobs,
    required this.es,
    required this.onSelect,
  });
  final DateTime day;
  final List<PlanningJob> jobs;
  final bool es;
  final ValueChanged<DateTime> onSelect;
  @override
  Widget build(BuildContext context) {
    final first = DateTime(day.year, day.month, 1);
    final count = DateTime(day.year, day.month + 1, 0).day;
    final offset = first.weekday - 1;
    return Column(
      children: [
        Row(
          children: [
            for (final label
                in es
                    ? ['L', 'M', 'X', 'J', 'V', 'S', 'D']
                    : ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(child: Center(child: Text(label))),
          ],
        ),
        for (var row = 0; row < ((offset + count) / 7).ceil(); row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final number = row * 7 + column - offset + 1;
                      if (number < 1 || number > count) {
                        return const SizedBox(height: 64);
                      }
                      final date = DateTime(day.year, day.month, number);
                      final total = jobs
                          .where(
                            (j) => j.inPeriod(
                              date,
                              DateTime(day.year, day.month, number + 1),
                            ),
                          )
                          .length;
                      return Semantics(
                        button: true,
                        selected: number == day.day,
                        label:
                            '${DateFormat.yMMMd(es ? 'es' : 'en').format(date)}, $total ${es ? 'trabajos' : 'jobs'}',
                        child: InkWell(
                          onTap: () => onSelect(date),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 64),
                            margin: const EdgeInsets.all(2),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: number == day.day
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text('$number'),
                                if (total > 0)
                                  Text(
                                    '$total',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: number == day.day
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onPrimaryContainer
                                              : null,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
