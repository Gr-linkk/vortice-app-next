import 'package:flutter/material.dart';
import 'package:vortice_app/features/coordination/coordination_entry.dart';
import 'package:vortice_app/features/operator/operator_evidence_photo.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_history_display_support.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart'
    show formatChecklistDateTime;
import 'package:vortice_app/features/checklists/checklist_attachment_support.dart';
import 'package:vortice_app/features/service_reports/service_report_media.dart';
import 'package:vortice_app/features/maintenance/maintenance_job_screen.dart'
    show MaintenanceEvidence;
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/features/checklists/saved_checklists_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/saved_checklist.dart';

class AssetChecklistHistoryScreen extends ConsumerWidget {
  final String assetId;
  final String assetName;
  final UserRole? role;

  const AssetChecklistHistoryScreen({
    super.key,
    required this.assetId,
    required this.assetName,
    required this.role,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showMaintenance =
        role != UserRole.operator && role != UserRole.clientOperator;
    if (!showMaintenance) {
      return Scaffold(
        appBar: AppBar(title: Text(assetName)),
        body: _ChecklistHistoryList(
          assetId: assetId,
          assetName: assetName,
          type: SavedChecklistType.operations,
          title: 'Operations Checklist History',
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(assetName),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Maintenance'),
              Tab(text: 'Operations'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ChecklistHistoryList(
              assetId: assetId,
              assetName: assetName,
              type: SavedChecklistType.maintenance,
              title: 'Maintenance Checklist History',
            ),
            _ChecklistHistoryList(
              assetId: assetId,
              assetName: assetName,
              type: SavedChecklistType.operations,
              title: 'Operations Checklist History',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistHistoryList extends ConsumerWidget {
  final String assetId;
  final String assetName;
  final SavedChecklistType type;
  final String title;

  const _ChecklistHistoryList({
    required this.assetId,
    required this.assetName,
    required this.type,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      savedChecklistsForAssetProvider((assetId: assetId, type: type)),
    );

    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          err.toString(),
          style: TextStyle(color: context.appColors.error),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'No saved checklists yet.',
              style: TextStyle(color: context.appColors.textSecondary),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (_, index) => _SavedChecklistCard(row: rows[index]),
        );
      },
    );
  }
}

class _SavedChecklistCard extends StatelessWidget {
  final SavedChecklist row;

  const _SavedChecklistCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final header = row.snapshot['header'] as Map<String, dynamic>? ?? const {};
    final items = (row.snapshot['items'] as List?)?.cast<Map>() ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(row.templateName),
        subtitle: Text(
          '${formatChecklistDateTime(row.submittedAt)} • ${row.sourceType}',
          style: TextStyle(
            fontSize: 12,
            color: context.appColors.textSecondary,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          CoordinationEntry(
            assetId: row.assetId,
            kind: 'checklist',
            subjectId: row.id,
            compact: true,
          ),
          for (final finding
              in (header['follow_up_faults'] as List? ?? const [])
                  .whereType<Map>())
            TextButton.icon(
              onPressed: () =>
                  context.push('/fleet/faults/${finding['fault_id']}'),
              icon: const Icon(Icons.warning_amber),
              label: Text(
                isSpanish(context)
                    ? 'Ver falla y seguimiento'
                    : 'View fault and follow-up',
              ),
            ),
          if (row.snapshot['managed_maintenance'] == true &&
              row.workOrderId != null)
            TextButton(
              onPressed: () =>
                  context.push('/maintenance/jobs/${row.workOrderId}'),
              child: Text(
                isSpanish(context)
                    ? 'Ver trabajo e informe'
                    : 'View job & report',
              ),
            ),
          _HeaderLine(
            label: es ? 'Realizada por' : 'Completed by',
            value: formatChecklistCompletedByDisplay(
              completedByName: header['completed_by_name'] as String?,
              completedBy: header['completed_by'] as String?,
              submittedBy: row.submittedBy,
            ),
          ),
          if ((row.submittedByRole ?? '').isNotEmpty)
            _HeaderLine(
              label: es ? 'Rol' : 'Role',
              value: formatChecklistSubmittedByRole(row.submittedByRole),
            ),
          _HeaderLine(
            label: es ? 'Enviada' : 'Submitted',
            value: formatChecklistDateTime(row.submittedAt),
          ),
          if ((row.snapshot['template'] as Map?)?['version'] != null)
            _HeaderLine(
              label: isSpanish(context) ? 'Versión' : 'Version',
              value: 'v${(row.snapshot['template'] as Map)['version']}',
            ),
          if (row.currentHours != null)
            _HeaderLine(
              label: es ? 'Horas actuales' : 'Current hours',
              value: '${row.currentHours}',
            ),
          if ((row.generalNotes ?? '').isNotEmpty)
            _HeaderLine(
              label: es ? 'Notas generales' : 'General notes',
              value: row.generalNotes!,
            ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Column(
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (es &&
                                (item['description_es'] as String? ?? '')
                                    .trim()
                                    .isNotEmpty
                            ? item['description_es']
                            : item['description_en'] ??
                                  (es ? 'Paso de la lista' : 'Checklist item'))
                        .toString(),
                  ),
                  subtitle: ((item['note'] ?? '').toString().isNotEmpty)
                      ? Text(
                          checklistRecordedValue(
                            Map<String, dynamic>.from(
                              item['definition'] as Map? ?? {},
                            ),
                            item['note'].toString(),
                          ),
                        )
                      : null,
                  trailing: Text(
                    (item['response'] ?? '').toString().toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (item['photo_path'] is String)
                  MaintenanceEvidence(path: item['photo_path'] as String),
                for (final photo in parseChecklistPhotoUrls(
                  item['photo_url'] as String?,
                ))
                  if (row.sourceType == 'operator')
                    OperatorEvidencePhoto(path: photo)
                  else
                    ServiceReportImage(
                      bucket: 'service-report-photos',
                      reference: photo,
                      height: 180,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderLine extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
