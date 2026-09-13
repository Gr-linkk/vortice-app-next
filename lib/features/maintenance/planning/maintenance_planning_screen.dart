import 'package:vortice_app/core/meter_units.dart';
import 'package:vortice_app/features/parts/parts_readiness_screen.dart';
import 'package:vortice_app/features/parts/parts_readiness_entry.dart';
import '../maintenance_recurrence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/list_label_order.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/work_order.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import '../maintenance_models.dart';
import '../maintenance_repository.dart';
import 'planning_models.dart';
import 'planning_repository.dart';
import 'schedule_job_screen.dart';
import '../work_focus.dart';
import '../create_work_entry.dart';

class MaintenancePlanningScreen extends ConsumerStatefulWidget {
  const MaintenancePlanningScreen({
    super.key,
    this.assetId,
    this.jobId,
    this.initialFilter,
  });
  final String? assetId, jobId, initialFilter;
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
  bool _showFilters = false;
  String? _calendarView;
  String? _filter, _status, _type, _component;
  String get _activeFilter => _filter ?? widget.initialFilter ?? 'open';

  @override
  void didUpdateWidget(covariant MaintenancePlanningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
      _view = 'list';
    }
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
    final focus = widget.assetId == null
        ? ref.watch(workFocusProvider).valueOrNull ?? WorkFocus.all
        : WorkFocus.all;
    final view =
        _view ??
        (widget.initialFilter != null ? 'list' : (manager ? 'week' : 'today'));
    if (!canUseMaintenance(profile?.role)) {
      return Scaffold(
        appBar: AppBar(title: Text(es ? 'Órdenes de trabajo' : 'Work orders')),
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
        title: Text(es ? 'Órdenes de trabajo' : 'Work orders'),
        actions: [
          IconButton(
            tooltip: es ? 'Buscar y filtrar' : 'Search & filters',
            isSelected:
                _showFilters ||
                _query.isNotEmpty ||
                _asset != null ||
                _person != null ||
                _status != null ||
                _type != null ||
                _component != null,
            onPressed: () => setState(() => _showFilters = !_showFilters),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            onPressed: _refresh,
            tooltip: es ? 'Actualizar' : 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: es ? 'Más opciones' : 'More options',
            onSelected: (value) {
              if (value == 'parts') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PartsReadinessScreen(),
                  ),
                );
              } else {
                _open(value);
              }
            },
            itemBuilder: (_) => [
              if (profile?.role == UserRole.owner ||
                  profile?.role == UserRole.employee)
                PopupMenuItem(
                  value: profile?.role == UserRole.owner
                      ? '/owner/work-orders/create'
                      : '/employee/work-orders/create',
                  child: Text(
                    es ? 'Crear trabajo de proveedor' : 'Create provider work',
                  ),
                ),
              PopupMenuItem(
                value: 'parts',
                child: Text(
                  es ? 'Existencias y compras' : 'Stock & purchasing',
                ),
              ),
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
          .watch(displayedMaintenancePlanningProvider(widget.assetId))
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
                for (final job in data.jobs) ...job.workers,
              };
              final selectedAsset = assets.containsKey(_asset) ? _asset : null;
              final selectedPerson = people.containsKey(_person)
                  ? _person
                  : null;
              final components = {
                for (final job in data.jobs)
                  if (job.componentName.isNotEmpty) job.componentName,
              };
              final scopedJobs =
                  data.jobs
                      .where(
                        (j) =>
                            j.matchesWorkFocus(focus) &&
                            (selectedAsset == null ||
                                j.assetId == selectedAsset) &&
                            (selectedPerson == null ||
                                j.workers.containsKey(selectedPerson)) &&
                            (_component == null ||
                                j.componentName == _component) &&
                            (_status == null || j.lifecycle == _status) &&
                            (_type == null || j.workType.dbValue == _type) &&
                            j.matchesSearch(_query, es),
                      )
                      .toList()
                    ..sort(comparePlanningJobs);
              final jobs = scopedJobs
                  .where(
                    (j) => j.matchesFilter(
                      _activeFilter,
                      profile?.id,
                      DateTime.now(),
                    ),
                  )
                  .toList();
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
                      'today' => j.inPeriod(
                        _day,
                        DateTime(_day.year, _day.month, _day.day + 1),
                      ),
                      'week' => j.inPeriod(week, until),
                      'month' => j.inPeriod(
                        _day,
                        DateTime(_day.year, _day.month, _day.day + 1),
                      ),
                      'list' => true,
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
                  key: const ValueKey('work-hub-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    if (widget.assetId == null && view != 'plans') ...[
                      const WorkFocusSelector(),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (manager)
                          FilledButton.icon(
                            onPressed: () => openNewWorkOrder(
                              context,
                              ref,
                              assetId: widget.assetId ?? selectedAsset,
                              planning: true,
                            ),
                            icon: const Icon(Icons.add),
                            label: Text(es ? 'Crear trabajo' : 'Create work'),
                          ),
                      ],
                    ),
                    if (_showFilters)
                      ExpansionTile(
                        initiallyExpanded: true,
                        tilePadding: EdgeInsets.zero,
                        maintainState: true,
                        title: Text(
                          es ? 'Buscar y filtrar' : 'Search & filters',
                        ),
                        subtitle:
                            _query.isNotEmpty ||
                                selectedAsset != null ||
                                selectedPerson != null
                            ? Text(es ? 'Filtros activos' : 'Filters active')
                            : null,
                        children: [
                          TextFormField(
                            initialValue: _query,
                            decoration: InputDecoration(
                              labelText: es
                                  ? 'Buscar trabajo o servicio'
                                  : 'Search asset, component, worker or work',
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
                                for (final asset
                                    in (assets.entries.toList()..sort(
                                      (a, b) =>
                                          compareListLabels(a.value, b.value),
                                    )))
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
                                for (final person
                                    in (people.entries.toList()..sort(
                                      (a, b) =>
                                          compareListLabels(a.value, b.value),
                                    )))
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
                          if (view != 'plans') ...[
                            const SizedBox(height: 16),
                            _searchFilter(
                              'work-status',
                              es ? 'Estado' : 'Status',
                              _status,
                              {
                                for (final status in const [
                                  'draft',
                                  'scheduled',
                                  'unscheduled',
                                  'in_progress',
                                  'on_hold',
                                  'pending_review',
                                  'returned',
                                  'completed',
                                ])
                                  status: maintenanceStatus(status, es),
                              },
                              (value) => setState(() => _status = value),
                              es,
                            ),
                            const SizedBox(height: 16),
                            _searchFilter(
                              'work-type',
                              es ? 'Tipo de trabajo' : 'Work type',
                              _type,
                              {
                                for (final type in WorkOrderJobType.values)
                                  type.dbValue: type.label(es),
                              },
                              (value) => setState(() => _type = value),
                              es,
                            ),
                            if (components.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _searchFilter(
                                'work-component',
                                es ? 'Componente' : 'Component',
                                _component,
                                {
                                  for (final component in components)
                                    component: component,
                                },
                                (value) => setState(() => _component = value),
                                es,
                              ),
                            ],
                            TextButton(
                              onPressed: () => setState(() {
                                _query = '';
                                _asset = null;
                                _person = null;
                                _status = null;
                                _type = null;
                                _component = null;
                                _showFilters = false;
                              }),
                              child: Text(
                                es
                                    ? 'Limpiar búsqueda y filtros'
                                    : 'Clear search & filters',
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                        ],
                      ),
                    const SizedBox(height: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const ValueKey('planning-collection'),
                        value: ['list', 'today', 'week', 'month'].contains(view)
                            ? 'calendar'
                            : view,
                        isExpanded: true,
                        itemHeight: null,
                        items: [
                          for (final option in [
                            (
                              'calendar',
                              es ? 'Órdenes de trabajo' : 'Work orders',
                            ),
                            (
                              'unscheduled',
                              es ? 'Sin programar' : 'Unscheduled',
                            ),
                            (
                              'attention',
                              es ? 'Por atender' : 'Needs attention',
                            ),
                            if (manager)
                              (
                                'plans',
                                es ? 'Planes de servicio' : 'Service plans',
                              ),
                          ])
                            DropdownMenuItem(
                              value: option.$1,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  option.$2,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _view = value == 'calendar'
                              ? (_calendarView ?? (manager ? 'week' : 'today'))
                              : value;
                        }),
                      ),
                    ),
                    if (view != 'plans') ...[
                      _workFilter(scopedJobs, profile?.id, es),
                    ],
                    if (['list', 'today', 'week', 'month'].contains(view)) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final option in [
                            ('list', es ? 'Lista' : 'List'),
                            ('today', es ? 'Día' : 'Day'),
                            ('week', es ? 'Semana' : 'Week'),
                            ('month', es ? 'Mes' : 'Month'),
                          ])
                            ChoiceChip(
                              label: Text(option.$2),
                              selected: view == option.$1,
                              onSelected: (_) => setState(() {
                                _view = option.$1;
                                _calendarView = option.$1;
                              }),
                            ),
                          TextButton(
                            onPressed: () => setState(() => _day = today),
                            child: Text(es ? 'Hoy' : 'Today'),
                          ),
                        ],
                      ),
                      if (view != 'list')
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
                      if (view == 'month')
                        PlanningMonth(
                          day: _day,
                          jobs: jobs,
                          es: es,
                          onSelect: (date) => setState(() {
                            _day = date;
                          }),
                        ),
                    ],
                    if (['today', 'week', 'month'].contains(view) &&
                        scopedJobs.any((j) => j.unscheduled))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          label: Text(
                            '${es ? 'Sin programar' : 'Unscheduled'} · ${scopedJobs.where((j) => j.unscheduled).length}',
                          ),
                          onPressed: () => setState(() {
                            _view = 'list';
                            _filter = 'unscheduled';
                          }),
                        ),
                      ),
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
                    ] else if (['today', 'week', 'month'].contains(view)) ...[
                      for (
                        var offset = 0;
                        offset < (view == 'week' ? 7 : 1);
                        offset++
                      )
                        PlanningDayAgenda(
                          day: view == 'week'
                              ? DateTime(
                                  week.year,
                                  week.month,
                                  week.day + offset,
                                )
                              : _day,
                          jobs: displayed,
                          es: es,
                          onOpen: (job) => _open(job.route),
                          onSchedule: (job) => _schedule(job, data.jobs),
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
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
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
                                  ? 'Son estimaciones, no disponibilidad confirmada. Las órdenes de trabajo sin hora no suman horas.'
                                  : 'Estimates, not confirmed availability. Untimed work orders add no booked hours.',
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      es
                          ? 'Horarios en la zona horaria de este dispositivo'
                          : 'Schedule times use this device’s time zone',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _searchFilter(
    String key,
    String label,
    String? value,
    Map<String, String> options,
    ValueChanged<String?> onChanged,
    bool es,
  ) => AppDropdownField<String>(
    key: ValueKey('$key-$value'),
    initialValue: options.containsKey(value) ? value! : '',
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: '', child: Text(es ? 'Todos' : 'All')),
      for (final option in options.entries)
        DropdownMenuItem(value: option.key, child: Text(option.value)),
    ],
    onChanged: (selected) => onChanged(selected == '' ? null : selected),
  );

  Widget _workFilter(List<PlanningJob> jobs, String? userId, bool es) {
    final options = {
      'open': es ? 'Abiertos' : 'Open',
      'mine': es ? 'Míos' : 'Mine',
      'unassigned': es ? 'Sin asignar' : 'Unassigned',
      'unscheduled': es ? 'Sin programar' : 'Unscheduled',
      'review': es ? 'Necesita revisión' : 'Needs review',
      'returned': es ? 'Devuelto' : 'Returned',
      'completed': es ? 'Completados' : 'Completed',
      'overdue': es ? 'Trabajo vencido' : 'Work overdue',
      'parts': es ? 'Esperando piezas' : 'Waiting for parts',
      'people': es ? 'Esperando personal' : 'Waiting for people',
      'blocked': es ? 'Otros bloqueos' : 'Other blocked work',
    };
    final filter = options.containsKey(_activeFilter) ? _activeFilter : 'open';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppDropdownField<String>(
        key: ValueKey('work-filter-$filter'),
        initialValue: filter,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: es ? 'Mostrar trabajo' : 'Show work',
        ),
        items: [
          for (final option in options.entries)
            DropdownMenuItem(
              value: option.key,
              child: Text(
                '${option.value} · ${jobs.where((j) => j.matchesFilter(option.key, userId, DateTime.now())).length}',
              ),
            ),
        ],
        onChanged: (value) => setState(() {
          _filter = value;
        }),
      ),
    );
  }

  Widget _empty(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(message),
  );

  Widget _jobCard(PlanningJob job, List<PlanningJob> jobs, bool es) => Card(
    child: Container(
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(
            color: job.conflict || job.overdue(DateTime.now())
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (job.ownEquipment ? WorkFocus.own : WorkFocus.customer).label(es),
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
            if (!job.providerService) Text(job.workType.label(es)),
            Text(
              '${job.assetName}${job.data['component_name'] == null ? '' : ' · ${job.data['component_name']}'}',
            ),
            Text(
              '${job.assigneeName.isEmpty ? (es ? 'Sin asignar' : 'Unassigned') : job.assigneeName} · ${job.lifecycleLabel(es)}${job.status == 'invoiced' ? (es ? ' · Facturado' : ' · Invoiced') : ''} · ${maintenancePriority(job.priority, es)}',
            ),
            if (job.data['due_meter'] != null)
              Text(
                '${es ? 'Objetivo del medidor' : 'Due meter'}: ${formatMeter(job.data['due_meter'] as num?, job.data['meter_unit'] as String?)}',
                style: job.meterDue
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
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
            PartsPlanningStatus(jobId: job.id),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (job.schedulable && job.start == null)
                  FilledButton(
                    onPressed: () => _schedule(job, jobs),
                    child: Text(es ? 'Programar' : 'Schedule'),
                  ),
                if (!job.schedulable || job.start != null)
                  FilledButton(
                    onPressed: () => _open(job.route),
                    child: Text(
                      job.providerService
                          ? (es ? 'Abrir orden de trabajo' : 'Open work order')
                          : job.schedulable ||
                                job.completed ||
                                job.status == 'pending_review'
                          ? (es ? 'Abrir trabajo' : 'Open work')
                          : (es ? 'Continuar trabajo' : 'Continue work'),
                    ),
                  )
                else
                  TextButton(
                    onPressed: () => _open(job.route),
                    child: Text(es ? 'Abrir trabajo' : 'Open work'),
                  ),
                if (job.schedulable && job.start != null)
                  TextButton(
                    onPressed: () => _schedule(job, jobs),
                    child: Text(es ? 'Reprogramar' : 'Reschedule'),
                  ),
              ],
            ),
          ],
        ),
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
                      ? 'Completa la configuración del plan'
                      : 'Complete plan setup')
                : '${plan.due ? (es ? 'Servicio pendiente · ' : 'Service due · ') : ''}${recurrenceDueText(plan.data, es)}',
          ),
          if (plan.hasJob)
            Text(
              es
                  ? 'Ya tiene una orden abierta.'
                  : 'Already has an open work order.',
            ),
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
                  onPressed: () => _open(
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

class PlanningDayAgenda extends StatelessWidget {
  const PlanningDayAgenda({
    super.key,
    required this.day,
    required this.jobs,
    required this.es,
    required this.onOpen,
    required this.onSchedule,
  });
  final DateTime day;
  final List<PlanningJob> jobs;
  final bool es;
  final ValueChanged<PlanningJob> onOpen, onSchedule;

  @override
  Widget build(BuildContext context) {
    final next = DateTime(day.year, day.month, day.day + 1);
    final entries = jobs.where((job) => job.inPeriod(day, next)).toList()
      ..sort(comparePlanningJobs);
    final locale = es ? 'es' : 'en';
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('calendar-agenda-${day.toIso8601String()}'),
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${DateFormat.yMMMMEEEEd(locale).format(day)} · ${entries.length}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                es
                    ? 'No hay órdenes de trabajo para este día.'
                    : 'No work orders scheduled for this day.',
              ),
            ),
          for (final job in entries)
            Card(
              key: ValueKey('calendar-work-${job.id}-${day.day}'),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(job),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(
                            job.start == null
                                ? (es ? 'Sin hora reservada' : 'No time booked')
                                : job.start!.isBefore(day)
                                ? (es
                                      ? 'Continúa del día anterior'
                                      : 'Continues from previous day')
                                : '${DateFormat.Hm(locale).format(job.start!)} – ${job.end!.isBefore(next) ? DateFormat.Hm(locale).format(job.end!) : DateFormat.MMMd(locale).add_Hm().format(job.end!)}',
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            job.lifecycleLabel(es),
                            style: theme.textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(job.title, style: theme.textTheme.titleMedium),
                      Text(job.assetName),
                      Text(
                        '${(job.ownEquipment ? WorkFocus.own : WorkFocus.customer).label(es)} · ${job.assigneeName.isEmpty ? (es ? 'Sin asignar' : 'Unassigned') : job.assigneeName}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (job.conflict)
                        Text(
                          es ? 'Conflicto de horario' : 'Schedule overlap',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: job.schedulable
                            ? IconButton(
                                tooltip: es ? 'Reprogramar' : 'Reschedule',
                                onPressed: () => onSchedule(job),
                                icon: const Icon(Icons.edit_calendar_outlined),
                              )
                            : const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Icon(Icons.chevron_right),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
    final today = planningDay(DateTime.now());
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            es
                ? 'Elige un día para ver sus órdenes de trabajo.'
                : 'Select a day to see its work orders.',
          ),
        ),
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final number = row * 7 + column - offset + 1;
                        if (number < 1 || number > count) {
                          return const SizedBox(height: 56);
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
                            key: ValueKey(
                              'calendar-day-${date.toIso8601String()}',
                            ),
                            onTap: () => onSelect(date),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 56),
                              margin: const EdgeInsets.all(2),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: number == day.day
                                    ? colors.primary
                                    : null,
                                border: Border.all(
                                  color: date == today
                                      ? colors.primary
                                      : colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '$number',
                                    style: TextStyle(
                                      color: number == day.day
                                          ? colors.onPrimary
                                          : null,
                                      fontWeight:
                                          date == today || number == day.day
                                          ? FontWeight.bold
                                          : null,
                                    ),
                                  ),
                                  if (total > 0)
                                    Container(
                                      margin: const EdgeInsets.only(top: 2),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: number == day.day
                                            ? colors.onPrimary
                                            : colors.secondaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          total > 9 ? '9+' : '$total',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: number == day.day
                                                    ? colors.primary
                                                    : colors
                                                          .onSecondaryContainer,
                                              ),
                                        ),
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
          ),
        const SizedBox(height: 12),
        Text(
          es
              ? 'Las insignias indican órdenes de trabajo.'
              : 'Badges show the number of work orders.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
