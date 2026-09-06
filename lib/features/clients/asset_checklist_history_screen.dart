import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_history_display_support.dart';
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
          style: const TextStyle(color: AppColors.error),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(
            child: Text(
              'No saved checklists yet.',
              style: TextStyle(color: AppColors.textSecondary),
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
    final header = row.snapshot['header'] as Map<String, dynamic>? ?? const {};
    final items = (row.snapshot['items'] as List?)?.cast<Map>() ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(row.templateName),
        subtitle: Text(
          '${row.submittedAt.toLocal()} • ${row.sourceType}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
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
            label: 'Completed by',
            value: formatChecklistCompletedByDisplay(
              completedByName: header['completed_by_name'] as String?,
              completedBy: header['completed_by'] as String?,
              submittedBy: row.submittedBy,
            ),
          ),
          if ((row.submittedByRole ?? '').isNotEmpty)
            _HeaderLine(
              label: 'Role',
              value: formatChecklistSubmittedByRole(row.submittedByRole),
            ),
          _HeaderLine(
            label: 'Submitted',
            value: '${row.submittedAt.toLocal()}',
          ),
          if (row.currentHours != null)
            _HeaderLine(label: 'Current hours', value: '${row.currentHours}'),
          if ((row.generalNotes ?? '').isNotEmpty)
            _HeaderLine(label: 'General notes', value: row.generalNotes!),
          const SizedBox(height: 8),
          ...items.map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                (item['description_en'] ?? 'Checklist item').toString(),
              ),
              subtitle: ((item['note'] ?? '').toString().isNotEmpty)
                  ? Text(item['note'].toString())
                  : null,
              trailing: Text(
                (item['response'] ?? '').toString().toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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
              style: const TextStyle(
                color: AppColors.textSecondary,
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
