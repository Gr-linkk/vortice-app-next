import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'planning/planning_repository.dart';
import 'maintenance_repository.dart';
import 'work_focus.dart';

Future<void> openNewWorkOrder(
  BuildContext context,
  WidgetRef ref, {
  String? assetId,
  bool planning = false,
  DateTime? selectedDay,
}) async {
  final ownRoute = Uri(
    path: '/maintenance/new',
    queryParameters: {
      if (assetId != null) 'assetId': assetId,
      if (planning) 'planning': 'true',
      if (selectedDay != null)
        'day': selectedDay.toIso8601String().split('T').first,
    },
  ).toString();
  final profile = ref.read(profileProvider).valueOrNull;
  var company = ref.read(organizationContextProvider).valueOrNull?.active;
  if (profile?.membershipManaged == true) {
    try {
      company = (await ref.read(organizationContextProvider.future)).active;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(context, error))));
      }
      return;
    }
    if (!context.mounted ||
        ref.read(profileProvider).valueOrNull?.id != profile?.id ||
        ref.read(profileProvider).valueOrNull?.orgId != profile?.orgId) {
      return;
    }
  }
  final focus = ref.read(workFocusProvider).valueOrNull ?? WorkFocus.all;
  if (assetId != null ||
      company?.providerEnabled != true ||
      focus == WorkFocus.own) {
    await context.push(ownRoute);
    return;
  }
  var customer = focus == WorkFocus.customer;
  if (focus == WorkFocus.all) {
    final es = isSpanish(context);
    final choice = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              es ? 'Nueva orden de trabajo' : 'New work order',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            ListTile(
              leading: const Icon(Icons.precision_manufacturing_outlined),
              title: Text(WorkFocus.own.label(es)),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: Text(WorkFocus.customer.label(es)),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    customer = choice;
  }
  if (!context.mounted) return;
  if (customer) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CustomerWorkCreateScreen(selectedDay: selectedDay),
      ),
    );
  } else {
    await context.push(ownRoute);
  }
}

final customerWorkCreationProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      await ref.watch(organizationContextProvider.future);
      return ref
          .watch(organizationWorkRepositoryProvider)
          .customerCreationContext();
    });

class CustomerWorkCreateScreen extends ConsumerStatefulWidget {
  const CustomerWorkCreateScreen({super.key, this.selectedDay});
  final DateTime? selectedDay;
  @override
  ConsumerState<CustomerWorkCreateScreen> createState() =>
      _CustomerWorkCreateScreenState();
}

class _CustomerWorkCreateScreenState
    extends ConsumerState<CustomerWorkCreateScreen> {
  final _title = TextEditingController(), _note = TextEditingController();
  final _operation = const Uuid().v4();
  String? _selection, _checklist, _error;
  late DateTime? _date = widget.selectedDay;
  bool _busy = false, _pending = false;
  bool get _frozen => _busy || _pending;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      fieldLabelText: isSpanish(context) ? 'Fecha' : 'Date',
      // Calendar cells clip two-digit days with enlarged text on narrow phones.
      // Keep the user's text size and offer the native date input in that case.
      initialEntryMode: MediaQuery.textScalerOf(context).scale(14) > 21
          ? DatePickerEntryMode.inputOnly
          : DatePickerEntryMode.calendar,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> equipment) async {
    setState(() {
      _busy = true;
      _pending = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(organizationWorkRepositoryProvider)
          .createCustomerWork(
            _operation,
            equipment['relationship_id'] as String,
            equipment['asset_id'] as String,
            _title.text,
            _note.text,
            serviceDate: _date,
            checklistTemplateId: _checklist,
          );
      ref.invalidate(workOrdersProvider);
      ref.invalidate(maintenancePlanningProvider);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.pop(context);
      if (widget.selectedDay != null && _date != null) {
        router.go(
          '/maintenance/planning?day=${_date!.toIso8601String().split('T').first}',
        );
      } else {
        router.push('/work-orders/$id');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(context, error);
          if (maintenanceWriteWasRejected(error)) _pending = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(es ? 'Nueva orden de trabajo' : 'New work order'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ref
                .watch(customerWorkCreationProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => AppErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(customerWorkCreationProvider),
                  ),
                  data: (data) {
                    final equipment = (data['equipment'] as List)
                        .cast<Map<String, dynamic>>();
                    final chosen = equipment
                        .where(
                          (row) =>
                              '${row['relationship_id']}:${row['asset_id']}' ==
                              _selection,
                        )
                        .firstOrNull;
                    final templates = (chosen?['templates'] as List? ?? [])
                        .cast<Map<String, dynamic>>();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (equipment.isEmpty)
                          Text(
                            es
                                ? 'El cliente debe conectar tu empresa y solicitar trabajo para compartir el equipo. Después podrás crear más órdenes para ese equipo.'
                                : 'Your customer needs to connect your company and request work to share their equipment. You can then create more work orders for that equipment.',
                          ),
                        if (equipment.isNotEmpty) ...[
                          AppDropdownField<String>(
                            initialValue: _selection,
                            decoration: InputDecoration(
                              labelText: es
                                  ? 'Equipo del cliente'
                                  : 'Customer equipment',
                            ),
                            items: [
                              for (final row in equipment)
                                DropdownMenuItem(
                                  value:
                                      '${row['relationship_id']}:${row['asset_id']}',
                                  child: Text(
                                    '${row['customer_name']} · ${row['asset_name']}',
                                  ),
                                ),
                            ],
                            onChanged: _frozen
                                ? null
                                : (value) => setState(() {
                                    _selection = value;
                                    _checklist = null;
                                  }),
                          ),
                          const SizedBox(height: 16),
                          AppDropdownField<String>(
                            key: ValueKey('creation-checklist-$_selection'),
                            initialValue: _checklist ?? '',
                            decoration: InputDecoration(
                              labelText: es ? 'Lista de revisión' : 'Checklist',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  es
                                      ? 'Sin lista adjunta'
                                      : 'No attached checklist',
                                ),
                              ),
                              for (final template in templates)
                                DropdownMenuItem(
                                  value: template['id'] as String,
                                  child: Text(
                                    '${template['name']} · v${template['version']}',
                                  ),
                                ),
                            ],
                            onChanged:
                                _frozen || chosen == null || templates.isEmpty
                                ? null
                                : (value) => setState(
                                    () =>
                                        _checklist = value == '' ? null : value,
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            chosen == null
                                ? (es
                                      ? 'Selecciona el equipo para ver sus listas disponibles.'
                                      : 'Choose equipment to see available checklists.')
                                : templates.isEmpty
                                ? (es
                                      ? 'No hay listas publicadas compatibles con este equipo.'
                                      : 'No published checklists match this equipment.')
                                : (es
                                      ? 'La lista seleccionada se adjuntará al crear la orden.'
                                      : 'The selected checklist will be attached when you create the work order.'),
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            key: const Key('creation-date'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              es ? 'Fecha programada' : 'Scheduled date',
                            ),
                            subtitle: Text(
                              _date == null
                                  ? (es ? 'Sin programar' : 'Unscheduled')
                                  : DateFormat.yMMMd(
                                      es ? 'es' : 'en',
                                    ).format(_date!),
                            ),
                            trailing: const Icon(Icons.calendar_today_outlined),
                            onTap: _frozen ? null : _pickDate,
                          ),
                          if (_date != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const Key('creation-clear-date'),
                                onPressed: _frozen
                                    ? null
                                    : () => setState(() => _date = null),
                                child: Text(
                                  es
                                      ? 'Dejar sin programar'
                                      : 'Leave unscheduled',
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _title,
                            enabled: !_frozen,
                            maxLength: 160,
                            decoration: InputDecoration(
                              labelText: es
                                  ? 'Título de la orden'
                                  : 'Work order title',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _note,
                            enabled: !_frozen,
                            maxLength: 4000,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: es
                                  ? 'Detalles del trabajo'
                                  : 'Work details',
                            ),
                          ),
                          if (_error != null)
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed:
                                _busy ||
                                    chosen == null ||
                                    _title.text.trim().length < 3
                                ? null
                                : () => _save(chosen),
                            child: Text(
                              _busy
                                  ? (es ? 'Guardando…' : 'Saving…')
                                  : _pending
                                  ? (es
                                        ? 'Reintentar el mismo guardado'
                                        : 'Retry same save')
                                  : (es
                                        ? 'Crear orden de trabajo'
                                        : 'Create work order'),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }
}
