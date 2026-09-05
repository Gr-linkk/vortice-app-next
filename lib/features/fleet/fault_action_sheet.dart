import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/fleet/fleet_models.dart';
import 'package:vortice_app/features/fleet/fleet_policy.dart';
import 'package:vortice_app/features/fleet/fleet_providers.dart';
import 'package:vortice_app/features/fleet/fleet_repository.dart';
import 'package:vortice_app/features/fleet/fleet_widgets.dart';

class FaultActionSheet extends ConsumerStatefulWidget {
  const FaultActionSheet({
    super.key,
    required this.fault,
    required this.action,
  });
  final FleetFault fault;
  final FaultAction action;
  @override
  ConsumerState<FaultActionSheet> createState() => _FaultActionSheetState();
}

class _FaultActionSheetState extends ConsumerState<FaultActionSheet> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _operationId = const Uuid().v4();
  String? _assignee;
  bool _saving = false;
  Object? _error;
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(fleetRepositoryProvider)
          .updateFault(
            fault: widget.fault,
            operationId: _operationId,
            action: widget.action,
            note: _note.text,
            assignedTo: _assignee,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = fleetSpanish(context);
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.action.label(es),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.fault.assetName,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (widget.action == FaultAction.assign) ...[
                    const SizedBox(height: 16),
                    ref
                        .watch(fleetAssigneesProvider(widget.fault.assetId))
                        .when(
                          loading: () => const LinearProgressIndicator(),
                          error: (error, _) => FleetError(
                            error: error,
                            onRetry: () => ref.invalidate(
                              fleetAssigneesProvider(widget.fault.assetId),
                            ),
                          ),
                          data: (members) => members.isEmpty
                              ? Text(
                                  es
                                      ? 'No hay responsables elegibles en esta flota.'
                                      : 'No eligible repair assignees in this fleet.',
                                )
                              : DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue:
                                      members.any((m) => m.id == _assignee)
                                      ? _assignee
                                      : null,
                                  decoration: InputDecoration(
                                    labelText: es
                                        ? 'Responsable'
                                        : 'Assigned to',
                                  ),
                                  items: members
                                      .map(
                                        (m) => DropdownMenuItem(
                                          value: m.id,
                                          child: Text(
                                            m.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _saving
                                      ? null
                                      : (id) => setState(() => _assignee = id),
                                  validator: (value) => value == null
                                      ? (es
                                            ? 'Selecciona un responsable'
                                            : 'Choose a repair assignee')
                                      : null,
                                ),
                        ),
                  ],
                  if (widget.action == FaultAction.resolve)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        es
                            ? 'Confirma la reparación realizada. La disponibilidad del equipo se cambia por separado.'
                            : 'Verify the completed repair. Asset availability is changed separately.',
                      ),
                    ),
                  if (widget.action == FaultAction.createWorkOrder)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        es
                            ? 'Crea una orden borrador vinculada a esta falla. La falla seguirá activa.'
                            : 'Create a draft work order linked to this fault. The fault remains active.',
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _note,
                    enabled: !_saving,
                    maxLines: 4,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: es ? 'Nota / motivo' : 'Note / reason',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? (es ? 'Explica el cambio' : 'Explain this change')
                        : null,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        fleetErrorMessage(_error!, es),
                        style: const TextStyle(color: AppColors.warning),
                      ),
                    ),
                  FilledButton(
                    onPressed:
                        _saving ||
                            (widget.action == FaultAction.assign &&
                                _assignee == null)
                        ? null
                        : _save,
                    child: Text(
                      _saving
                          ? (es ? 'Guardando…' : 'Saving…')
                          : widget.action.label(es),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text(es ? 'Cancelar' : 'Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
