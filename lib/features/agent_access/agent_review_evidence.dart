import 'package:vortice_app/core/meter_units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'maintenance_documents_repository.dart';
import 'maintenance_documents_screen.dart';

Map<String, dynamic> reviewMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> reviewRows(dynamic value) =>
    value is List ? value.map(reviewMap).toList() : <Map<String, dynamic>>[];
String reviewHours(num? value, [String unit = 'hours']) => value == null || !value.isFinite
    ? '—'
    : '${value == value.roundToDouble() ? value.toInt() : value} ${meterSymbol(unit)}';
String reviewDate(BuildContext context, dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return date == null
      ? '—'
      : MaterialLocalizations.of(context).formatCompactDate(date);
}

class AgentReviewEvidence {
  AgentReviewEvidence(this.data);
  final Map<String, dynamic> data;
  Map<String, dynamic> get proposal => reviewMap(data['proposal']);
  Map<String, dynamic> get draft => reviewMap(proposal['draft']);
  Map<String, dynamic> get catalog => reviewMap(data['catalog']);
  Map<String, dynamic> get component =>
      reviewRows(
        catalog['components'],
      ).where((e) => e['id'] == draft['engine_id']).firstOrNull ??
      {};
  Map<String, dynamic>? get plan => reviewRows(catalog['plans'])
      .where(
        (p) =>
            p['id'] ==
            (draft['existing_plan_id'] ?? proposal['applied_plan_id']),
      )
      .firstOrNull;
  String get unit => component['meter_unit'] as String? ?? 'hours';
  String get proposalUnit => draft['meter_unit'] as String? ?? 'hours';
  bool get meterMatches => unit == proposalUnit;
  num? get current => component['current_hours'] as num?;
  num? get baseline => plan?['last_service_hours'] as num?;
  num get interval => draft['interval_hours'] as num;
  num? get proposedDue => baseline == null || !meterMatches ? null : baseline! + interval;
  bool get applied => proposal['applied_plan_id'] != null;
  bool get missingPlan => draft['existing_plan_id'] != null && plan == null;
  bool get checklistReady =>
      draft['checklist_procedure_id'] == null ||
      (data['procedure']?['published_template_id'] != null &&
          data['procedure']?['archived'] != true);
  bool get canEdit =>
      checklistReady &&
      meterMatches &&
      !missingPlan &&
      catalog['can_plan'] != false &&
      component.isNotEmpty;
}

class AgentSectionCard extends StatelessWidget {
  const AgentSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class ReviewFact extends StatelessWidget {
  const ReviewFact(this.label, this.value, {super.key, this.detail});
  final String label, value;
  final String? detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        if (detail != null)
          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class AgentProposalSummary extends StatelessWidget {
  const AgentProposalSummary({super.key, required this.evidence});
  final AgentReviewEvidence evidence;
  @override
  Widget build(BuildContext context) {
    final e = evidence, es = isSpanish(context);
    final remaining = e.proposedDue == null || e.current == null
        ? null
        : e.proposedDue! - e.current!;
    return AgentSectionCard(
      title: e.applied
          ? (es ? 'Guardado después de revisar' : 'Saved after review')
          : (es ? 'El cambio propuesto' : 'The proposed change'),
      icon: e.applied ? Icons.task_alt : Icons.compare_arrows,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.plan != null)
            ReviewFact(
              e.applied
                  ? (es ? 'Intervalo guardado' : 'Saved interval')
                  : (es ? 'Intervalo actual' : 'Current interval'),
              reviewHours(e.plan!['interval_hours'] as num?, e.unit),
            ),
          ReviewFact(
            e.applied
                ? (es
                      ? 'Propuesta original del agente'
                      : 'Original agent proposal')
                : (es ? 'Intervalo propuesto' : 'Proposed interval'),
            reviewHours(e.interval, e.proposalUnit),
          ),
          if (!e.applied) ...[
            const Divider(),
            ReviewFact(
              es ? 'Próximo servicio propuesto' : 'Proposed next service',
              e.proposedDue == null
                  ? (es
                        ? 'Confirma el último servicio'
                        : 'Confirm last service first')
                  : reviewHours(e.proposedDue, e.unit),
              detail: e.proposedDue == null
                  ? (es
                        ? 'El manual da el intervalo. El historial determina dónde empieza.'
                        : 'The manual gives the interval. Service history determines where it starts.')
                  : '${reviewHours(e.baseline, e.unit)} + ${reviewHours(e.interval, e.unit)} = ${reviewHours(e.proposedDue, e.unit)}',
            ),
            if (remaining != null)
              Text(
                remaining < 0
                    ? '${reviewHours(-remaining, e.unit)} ${es ? 'de atraso según la propuesta' : 'overdue under this proposal'}'
                    : '${reviewHours(remaining, e.unit)} ${es ? 'restantes según la propuesta' : 'remaining under this proposal'}',
              ),
          ],
          if ((e.draft['notes'] as String? ?? '').trim().isNotEmpty) ...[
            const Divider(),
            Text(
              es ? 'Notas del agente' : 'Agent notes',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Text(e.draft['notes'] as String),
          ],
        ],
      ),
    );
  }
}

class AgentEquipmentEvidence extends StatelessWidget {
  const AgentEquipmentEvidence({super.key, required this.evidence});
  final AgentReviewEvidence evidence;
  @override
  Widget build(BuildContext context) {
    final e = evidence, es = isSpanish(context);
    final meter = reviewMap(e.data['meter_log']);
    return AgentSectionCard(
      title: es
          ? 'Medidor e historial de esta tarea'
          : 'Meter and this task’s history',
      icon: Icons.speed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReviewFact(
            es ? 'Componente' : 'Component',
            e.component['label'] as String? ??
                (es ? 'No disponible' : 'Unavailable'),
          ),
          ReviewFact(
            es ? 'Lectura actual registrada' : 'Recorded current meter',
            e.current == null
                ? (es ? 'Desconocidas' : 'Unknown')
                : reviewHours(e.current, e.unit),
            detail: meter['logged_at'] == null
                ? (es
                      ? 'Sin fecha de lectura. Verifica el medidor.'
                      : 'No reading date recorded. Verify the meter.')
                : '${es ? 'Última lectura' : 'Latest meter entry'}: ${reviewHours(meter['hours'] as num?, meter['meter_unit'] as String? ?? e.unit)} · ${reviewDate(context, meter['logged_at'])}',
          ),
          ReviewFact(
            es ? 'Último servicio de esta tarea' : 'Last service for this task',
            e.baseline == null
                ? (es ? 'Por confirmar' : 'Needs confirmation')
                : reviewHours(e.baseline, e.unit),
          ),
          if (e.draft['recorded_current_hours'] != null &&
              e.current != null &&
              e.draft['recorded_current_hours'] != e.current)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                es
                    ? 'El medidor cambió desde la propuesta (${reviewHours(e.draft['recorded_current_hours'] as num?, e.unit)}). El cálculo usa el medidor actual.'
                    : 'The meter changed since this proposal (${reviewHours(e.draft['recorded_current_hours'] as num?, e.unit)}). The calculation uses the current meter.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Text(
            es
                ? 'Una lectura de cero no demuestra que el equipo sea nuevo. El servicio de otra tarea no reinicia esta.'
                : 'A zero reading does not prove new equipment. Servicing another task does not reset this one.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final agentSourcePreviewProvider = FutureProvider.autoDispose
    .family<MaintenanceDocumentPage, (String, int)>(
      (ref, key) async => MaintenanceDocumentPage(
        await ref
            .watch(maintenanceDocumentsRepositoryProvider)
            .page(key.$1, key.$2),
      ),
    );

class AgentSourceEvidence extends ConsumerStatefulWidget {
  const AgentSourceEvidence({super.key, required this.evidence});
  final AgentReviewEvidence evidence;
  @override
  ConsumerState<AgentSourceEvidence> createState() => _SourceEvidenceState();
}

class _SourceEvidenceState extends ConsumerState<AgentSourceEvidence> {
  bool preview = false;
  @override
  Widget build(BuildContext context) {
    final e = widget.evidence, es = isSpanish(context);
    final key = (
      e.proposal['document_id'] as String,
      e.draft['source_page'] as int,
    );
    return AgentSectionCard(
      title: es ? 'La fuente del intervalo' : 'Where the interval comes from',
      icon: Icons.menu_book_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.data['document']?['title'] as String? ??
                (es ? 'Manual de mantenimiento' : 'Maintenance manual'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text('${es ? 'Página' : 'Page'} ${key.$2}'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
              ),
            ),
            child: SelectableText(e.draft['source_quote'] as String),
          ),
          const SizedBox(height: 8),
          Text(
            es
                ? 'Cita extraída por el agente, sin verificar. Compárala con la página original.'
                : 'Agent-extracted quote, unverified. Compare it with the original page.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: () => setState(() => preview = !preview),
            icon: Icon(preview ? Icons.expand_less : Icons.expand_more),
            label: Text(
              preview
                  ? (es ? 'Ocultar página' : 'Hide page')
                  : '${es ? 'Ver página' : 'View source page'} ${key.$2}',
            ),
          ),
          if (preview)
            ref
                .watch(agentSourcePreviewProvider(key))
                .when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => TextButton(
                    onPressed: () =>
                        ref.invalidate(agentSourcePreviewProvider(key)),
                    child: Text(
                      es
                          ? 'No se pudo cargar la página. Reintentar.'
                          : 'Could not load the page. Retry.',
                    ),
                  ),
                  data: (page) => Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          height: 280,
                          width: double.infinity,
                          child: ColoredBox(
                            color: Colors.white,
                            child: Image.memory(
                              page.bytes,
                              fit: BoxFit.contain,
                              frameBuilder:
                                  (context, child, frame, synchronous) =>
                                      frame == null && !synchronous
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : child,
                              errorBuilder: (context, error, stack) => Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    es
                                        ? 'Imagen ilegible. Consulta otra copia del manual.'
                                        : 'Unreadable image. Check another copy of the manual.',
                                    style: const TextStyle(color: Colors.black),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => MaintenanceSourcePageScreen(
                              document: key.$1,
                              page: key.$2,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.zoom_in),
                        label: Text(es ? 'Ampliar página' : 'Open full page'),
                      ),
                    ],
                  ),
                ),
          const SizedBox(height: 8),
          Text(
            es
                ? 'Revisa también las advertencias y condiciones. Las reglas de calendario requieren seguimiento aparte.'
                : 'Check warnings and conditions too. Calendar rules require separate tracking.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class AgentServiceEvidence extends StatelessWidget {
  const AgentServiceEvidence({super.key, required this.evidence});
  final AgentReviewEvidence evidence;
  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context),
        rows = reviewRows(evidence.data['approved_services']);
    final e = evidence;
    return AgentSectionCard(
      title: es
          ? 'Servicios aprobados del componente'
          : 'Approved component services',
      icon: Icons.history,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            Text(
              es
                  ? 'No hay servicios aprobados registrados para este componente. Confirma el historial antes de introducir la base.'
                  : 'No approved services are recorded for this component. Confirm its history before entering a baseline.',
            ),
          for (final row in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row['title'] as String),
              subtitle: Text(
                '${reviewDate(context, row['service_applied_at'])} · ${reviewHours(row['hours_at_end'] as num?, row['meter_unit'] as String? ?? e.unit)}\n${row['matches_task'] == true ? (es ? 'Vinculado a esta tarea' : 'Linked to this task') : (es ? 'Otra tarea: no usar como base sin verificar' : 'Other task: verify before using as baseline')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push('/maintenance/jobs/${row['work_order_id']}'),
            ),
          if (evidence.data['services_truncated'] == true)
            Text(
              es
                  ? 'Se muestran los 20 servicios aprobados más recientes.'
                  : 'Showing the 20 most recent approved services.',
            ),
        ],
      ),
    );
  }
}
