import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/maintenance/maintenance_models.dart';
import 'package:vortice_app/features/maintenance/maintenance_repository.dart';
import 'assurance_repository.dart';
import 'assurance_form.dart';

class AssuranceScreen extends ConsumerStatefulWidget {
  const AssuranceScreen({super.key, this.asset});
  final String? asset;
  @override
  ConsumerState<AssuranceScreen> createState() => _AssuranceScreenState();
}

class _AssuranceScreenState extends ConsumerState<AssuranceScreen> {
  String _filter = 'all', _search = '';
  Future<void> _form(
    String action, {
    Map<String, dynamic> item = const {},
    Map<String, dynamic> catalog = const {},
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => AssuranceForm(
          action: action,
          asset: widget.asset ?? item['asset_id'] as String,
          item: item,
          catalog: catalog,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final inspections = ref.watch(inspectionRegisterProvider(widget.asset));
    final catalog = widget.asset == null
        ? null
        : ref.watch(assuranceContextProvider(widget.asset!));
    void refresh() {
      ref.invalidate(inspectionRegisterProvider(widget.asset));
      if (widget.asset != null) {
        ref.invalidate(assuranceContextProvider(widget.asset!));
      }
    }

    Widget retry(Object error) => Column(
      children: [
        Text(maintenanceError(error, es)),
        TextButton(
          onPressed: refresh,
          child: Text(es ? 'Reintentar' : 'Try again'),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.asset == null
              ? (es ? 'Inspecciones de la flota' : 'Fleet inspections')
              : (es ? 'Custodia e inspecciones' : 'Custody & inspections'),
        ),
        actions: [
          IconButton(
            onPressed: refresh,
            tooltip: es ? 'Actualizar' : 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            refresh();
            await ref.read(inspectionRegisterProvider(widget.asset).future);
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (catalog != null)
                catalog.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => retry(e),
                  data: (data) {
                    final asset = data['asset'] as Map?;
                    if (asset == null) {
                      return Text(
                        es ? 'Equipo no encontrado' : 'Asset not found',
                      );
                    }
                    final custody = data['custody'] as Map?;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset['name'] as String,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  es
                                      ? 'Ubicación y responsable'
                                      : 'Location & responsibility',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  custody?['site'] as String? ??
                                      asset['location'] as String? ??
                                      (es
                                          ? 'Sin ubicación'
                                          : 'No location recorded'),
                                ),
                                Text(
                                  custody?['responsible_name'] as String? ??
                                      (es
                                          ? 'Sin responsable asignado'
                                          : 'No responsible person assigned'),
                                ),
                                if (custody != null)
                                  Text(
                                    assuranceLabel(
                                      custody['lifecycle'] as String,
                                      es,
                                    ),
                                  ),
                                if (data['can_manage'] == true)
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _form('transfer', catalog: data),
                                    icon: const Icon(Icons.move_down),
                                    label: Text(
                                      es
                                          ? 'Registrar traslado'
                                          : 'Record transfer',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        ExpansionTile(
                          title: Text(
                            es ? 'Historial de traslados' : 'Transfer history',
                          ),
                          children: [
                            if (maintenanceRows(data['transfers']).isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  es
                                      ? 'No hay traslados registrados.'
                                      : 'No transfers recorded.',
                                ),
                              ),
                            for (final event in maintenanceRows(
                              data['transfers'],
                            ))
                              ListTile(
                                title: Text(
                                  '${(event['previous'] as Map?)?['site'] ?? '—'} → ${(event['current_state'] as Map)['site']}',
                                ),
                                subtitle: Text(
                                  '${(event['current_state'] as Map)['responsible_name']} · ${assuranceLabel((event['current_state'] as Map)['lifecycle'] as String, es)}\n${event['reason']}\n${event['actor_name']} · ${maintenanceDate(event['created_at'] as String, es)}',
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (data['can_manage'] == true)
                              FilledButton.icon(
                                onPressed: () => _form('create', catalog: data),
                                icon: const Icon(Icons.add),
                                label: Text(
                                  es ? 'Añadir inspección' : 'Add inspection',
                                ),
                              ),
                            OutlinedButton(
                              onPressed: () => context.push('/assurance'),
                              child: Text(
                                es
                                    ? 'Ver toda la flota'
                                    : 'View fleet inspections',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              Text(
                es
                    ? 'Inspecciones y certificados'
                    : 'Inspections & certificates',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: es
                      ? 'Buscar equipo, sitio o inspección'
                      : 'Search asset, site or inspection',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) =>
                    setState(() => _search = v.toLowerCase().trim()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final filter in [
                    'all',
                    'expired',
                    'upcoming',
                    'pending',
                    'unverified',
                    'current',
                  ])
                    ChoiceChip(
                      label: Text(
                        filter == 'all'
                            ? (es ? 'Todas' : 'All')
                            : assuranceLabel(filter, es),
                      ),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              inspections.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => retry(e),
                data: (items) {
                  final visible = items
                      .where(
                        (item) =>
                            (_filter == 'all' ||
                                (_filter == 'pending'
                                    ? item['pending'] != null
                                    : inspectionState(item, DateTime.now()) ==
                                          _filter)) &&
                            [
                              item['title'],
                              item['asset_name'],
                              item['site'],
                              item['responsible_name'],
                            ].join(' ').toLowerCase().contains(_search),
                      )
                      .toList();
                  if (visible.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        es
                            ? 'No hay inspecciones para esta selección.'
                            : 'No inspections match this selection.',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final item in visible)
                        InspectionCard(
                          item: item,
                          onAction: (action) => _form(action, item: item),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InspectionCard extends StatelessWidget {
  const InspectionCard({super.key, required this.item, required this.onAction});
  final Map<String, dynamic> item;
  final ValueChanged<String> onAction;
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context),
        status = inspectionState(item, DateTime.now());
    final approved = item['approved'] as Map?,
        pending = item['pending'] as Map?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['title'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${item['asset_name']}${item['component_name'] == null ? '' : ' · ${item['component_name']}'}',
            ),
            if (item['site'] != null)
              Text('${item['site']} · ${item['responsible_name'] ?? ''}'),
            if (item['lifecycle'] != null)
              Text(assuranceLabel(item['lifecycle'] as String, es)),
            const SizedBox(height: 8),
            Text(
              assuranceLabel(status, es),
              style: TextStyle(
                color: status == 'expired'
                    ? Theme.of(context).colorScheme.error
                    : null,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (approved != null)
              Text(
                '${es ? 'Vence' : 'Expires'}: ${maintenanceDate(approved['expires_on'] as String, es)}',
              ),
            if (pending != null)
              Text(
                es
                    ? 'Renovación pendiente de revisión'
                    : 'Renewal awaiting review',
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item['can_submit'] == true && pending == null)
                  OutlinedButton(
                    onPressed: () => onAction('submit'),
                    child: Text(es ? 'Enviar renovación' : 'Submit renewal'),
                  ),
                OutlinedButton(
                  onPressed: () =>
                      context.push('/assurance/assets/${item['asset_id']}'),
                  child: Text(es ? 'Ver equipo' : 'Open asset'),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                es
                    ? 'Evidencia e historial de revisión'
                    : 'Evidence & review history',
              ),
              initiallyExpanded: pending != null,
              children: [
                if (maintenanceRows(item['versions']).isEmpty)
                  Text(
                    es
                        ? 'Todavía no hay renovaciones.'
                        : 'No renewals submitted yet.',
                  ),
                for (final version in maintenanceRows(item['versions']))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          assuranceLabel(version['status'] as String, es),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          '${maintenanceDate(version['inspected_on'] as String, es)} → ${maintenanceDate(version['expires_on'] as String, es)}',
                        ),
                        Text(
                          '${es ? 'Procedimiento' : 'Procedure'}: ${version['procedure_notes']}',
                        ),
                        Text(
                          '${es ? 'Resultados' : 'Results'}: ${version['result_notes']}',
                        ),
                        Text(
                          '${version['submitted_name']} · ${maintenanceDate(version['submitted_at'] as String, es)}',
                        ),
                        if (version['review_note'] != null)
                          Text(
                            '${version['reviewed_name']} · ${maintenanceDate(version['reviewed_at'] as String, es)}\n${version['review_note']}',
                          ),
                        const SizedBox(height: 8),
                        InspectionEvidence(
                          path: version['evidence_path'] as String,
                        ),
                        if (version['status'] == 'pending' &&
                            item['can_manage'] == true)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: () => onAction('approve'),
                                child: Text(
                                  es ? 'Aprobar renovación' : 'Approve renewal',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => onAction('return'),
                                child: Text(
                                  es ? 'Devolver renovación' : 'Return renewal',
                                ),
                              ),
                            ],
                          ),
                        const Divider(),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class InspectionEvidence extends ConsumerWidget {
  const InspectionEvidence({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = isSpanish(context);
    Widget retry() => TextButton.icon(
      onPressed: () => ref.invalidate(inspectionImageProvider(path)),
      icon: const Icon(Icons.refresh),
      label: Text(es ? 'Reintentar foto' : 'Retry photo'),
    );
    return ref
        .watch(inspectionImageProvider(path))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => retry(),
          data: (url) => Image.network(
            url,
            height: 200,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => retry(),
          ),
        );
  }
}
