import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/maintenance/maintenance_refresh.dart';

class AgentWorkProposalRepository {
  AgentWorkProposalRepository(this.client, this.actor);
  final SupabaseClient client;
  final String actor;
  Future<dynamic> _call(String name, Map<String, dynamic> params) async {
    if (client.auth.currentUser?.id != actor) throw StateError('Account changed');
    final result = await client.rpc(name, params: params).timeout(const Duration(seconds: 20));
    if (client.auth.currentUser?.id != actor) throw StateError('Account changed');
    return result;
  }
  Future<List<Map<String, dynamic>>> load(({String? proposal, String? fleet}) query) async =>
      (await _call('agent_work_review_context', {'p_proposal': query.proposal, 'p_client': query.fleet}) as List)
          .map((row) => Map<String, dynamic>.from(row as Map)).toList();
  Future<void> review(String proposal, String operation, String action) async {
    await _call('review_agent_work_proposal', {'p_proposal': proposal, 'p_operation': operation, 'p_action': action});
  }
}

final agentWorkProposalRepositoryProvider = Provider((ref) => AgentWorkProposalRepository(supabase, ref.watch(sessionProvider)?.user.id ?? ''));
final agentWorkProposalsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, ({String? proposal, String? fleet})>(
    (ref, query) => ref.watch(agentWorkProposalRepositoryProvider).load(query));

class AgentWorkProposalsScreen extends ConsumerWidget {
  const AgentWorkProposalsScreen({super.key, this.proposalId, this.fleet});
  final String? proposalId, fleet;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final query = (proposal: proposalId, fleet: fleet);
    final state = ref.watch(agentWorkProposalsProvider(query));
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Propuestas de trabajo' : 'Work proposals'), actions: [IconButton(
        tooltip: es ? 'Actualizar' : 'Refresh', onPressed: () => ref.invalidate(agentWorkProposalsProvider(query)), icon: const Icon(Icons.refresh))]),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(agentWorkProposalsProvider(query)), child: Text(es ? 'No disponible. Conecta y reintenta.' : 'Unavailable. Connect and retry.'))),
        data: (proposals) => proposals.isEmpty
            ? Center(child: Text(es ? 'No hay propuestas pendientes.' : 'No work proposals waiting.'))
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (proposals.length == 100) Text(es ? 'Primeras 100 propuestas. Al revisarlas aparecerán las siguientes.' : 'First 100 proposals. More appear as these are reviewed.'),
                for (final proposal in proposals)
                AgentWorkProposalCard(key: ValueKey('${ref.watch(sessionProvider)?.user.id}:${proposal['id']}'), proposal: proposal,
                  onReviewed: () { ref.invalidate(agentWorkProposalsProvider); refreshMaintenance(ref, jobId: proposal['work_order_id'] as String); })]),
      ),
    );
  }
}

class AgentWorkProposalCard extends ConsumerStatefulWidget {
  const AgentWorkProposalCard({super.key, required this.proposal, required this.onReviewed});
  final Map<String, dynamic> proposal;
  final VoidCallback onReviewed;
  @override
  ConsumerState<AgentWorkProposalCard> createState() => _AgentWorkProposalCardState();
}

class _AgentWorkProposalCardState extends ConsumerState<AgentWorkProposalCard> {
  String? _operation, _action, _error;
  bool _busy = false;
  @override
  void didUpdateWidget(covariant AgentWorkProposalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.proposal, widget.proposal) && !_busy) {
      _operation = null;
      _action = null;
      _error = null;
    }
  }
  Future<void> _review(String action) async {
    if (_busy || (_action != null && _action != action)) return;
    final es = Localizations.localeOf(context).languageCode == 'es';
    _operation ??= const Uuid().v4();
    _action = action;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(agentWorkProposalRepositoryProvider).review(widget.proposal['id'] as String, _operation!, action);
      if (!mounted) return;
      widget.onReviewed();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = es
          ? 'No se confirmó el resultado. Reintenta la misma acción o actualiza para comprobar el estado. Si el trabajo cambió, rechaza esta propuesta y pide una nueva.'
          : 'Result not confirmed. Retry the same action or refresh to check its status. If the work changed, reject this proposal and ask for a new one.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final p = widget.proposal;
    final input = Map<String, dynamic>.from(p['input'] as Map);
    final current = Map<String, dynamic>.from(p['current'] as Map);
    final fields = switch (p['action']) {
      'assign_work_order' => ['assigned_to'],
      'schedule_work_order' => ['assigned_to', 'due_date', 'planned_start', 'estimated_minutes', 'priority'],
      _ => ['title', 'description', 'job_type', 'expected_materials', 'priority'],
    };
    String label(String key) => switch (key) {
      'assigned_to' => es ? 'Responsable' : 'Assigned person',
      'due_date' => es ? 'Fecha límite' : 'Deadline',
      'planned_start' => es ? 'Inicio previsto' : 'Planned start',
      'estimated_minutes' => es ? 'Duración (minutos)' : 'Duration (minutes)',
      'priority' => es ? 'Prioridad' : 'Priority',
      'title' => es ? 'Título' : 'Title',
      'description' => es ? 'Instrucciones' : 'Instructions',
      'job_type' => es ? 'Tipo de trabajo' : 'Work type',
      _ => es ? 'Materiales previstos' : 'Expected materials',
    };
    String value(String key, Map<String, dynamic> data, bool proposed) {
      var result = data[key];
      if (key == 'assigned_to' && result != null && result != '') result = p[proposed ? 'proposed_person' : 'current_person'] ?? (es ? 'Persona no disponible' : 'Person unavailable');
      if (result == null || result == '') return es ? 'Sin definir' : 'Not set';
      if (key == 'planned_start') {
        final date = DateTime.tryParse(result.toString())?.toLocal();
        if (date != null) return '${MaterialLocalizations.of(context).formatMediumDate(date)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
      }
      return result.toString().replaceAll('_', ' ');
    }
    final pending = p['status'] == 'pending';
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(p['work_title'] as String, style: Theme.of(context).textTheme.titleLarge),
      Text('${p['asset_name']} · ${p['connection_label']}'),
      const SizedBox(height: 12),
      Text(es ? 'Revisa el cambio antes de aplicarlo al trabajo.' : 'Review the change before applying it to the work.'),
      for (final field in fields) Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label(field), style: Theme.of(context).textTheme.titleSmall),
        Text('${es ? 'Actual' : 'Current'}: ${value(field, current, false)}'),
        Text('${es ? 'Propuesto' : 'Proposed'}: ${value(field, input, true)}'),
      ])),
      if (input['note'] != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(input['note'] as String)),
      TextButton.icon(onPressed: () => context.push('/maintenance/jobs/${p['work_order_id']}'), icon: const Icon(Icons.open_in_new), label: Text(es ? 'Abrir trabajo' : 'Open work')),
      if (pending && p['can_apply'] != true) Text(es ? 'El trabajo cambió desde esta propuesta. Recházala y pide una propuesta actualizada.' : 'Work changed since this proposal. Reject it and ask for an updated proposal.'),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (pending) Wrap(spacing: 12, children: [
        FilledButton(onPressed: _busy || p['can_apply'] != true || (_action != null && _action != 'apply') ? null : () => _review('apply'), child: Text(es ? 'Aplicar este cambio' : 'Apply this change')),
        TextButton(onPressed: _busy || (_action != null && _action != 'reject') ? null : () => _review('reject'), child: Text(es ? 'Rechazar propuesta' : 'Reject proposal')),
      ]) else Text(p['status'] == 'applied' ? (es ? 'Cambio aplicado' : 'Change applied') : (es ? 'Propuesta rechazada' : 'Proposal rejected')),
      if (_busy) const LinearProgressIndicator(),
    ])));
  }
}
