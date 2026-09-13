import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'planning/planning_repository.dart';
import 'work_focus.dart';

Future<void> openNewWorkOrder(
  BuildContext context,
  WidgetRef ref, {
  String? assetId,
  bool planning = false,
}) async {
  final ownRoute = Uri(
    path: '/maintenance/new',
    queryParameters: {
      if (assetId != null) 'assetId': assetId,
      if (planning) 'planning': 'true',
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CustomerWorkSheet(),
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

class CustomerWorkSheet extends ConsumerStatefulWidget {
  const CustomerWorkSheet({super.key});
  @override
  ConsumerState<CustomerWorkSheet> createState() => _CustomerWorkSheetState();
}

class _CustomerWorkSheetState extends ConsumerState<CustomerWorkSheet> {
  final _title = TextEditingController(), _note = TextEditingController();
  final _operation = const Uuid().v4();
  String? _selection, _error;
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> equipment) async {
    setState(() {
      _busy = true;
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
          );
      ref.invalidate(workOrdersProvider);
      ref.invalidate(maintenancePlanningProvider);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.push('/work-orders/$id');
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: ref
            .watch(customerWorkCreationProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      es ? 'Nueva orden de trabajo' : 'New work order',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
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
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _selection = value),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _title,
                        enabled: !_busy,
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
                        enabled: !_busy,
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
    );
  }
}
