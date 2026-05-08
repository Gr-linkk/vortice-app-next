import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/saved_checklist_history_writer.dart';
import 'package:vortice_app/features/service_intervals/preventative_maintenance_completion.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

final maintenanceChecklistSubmissionProvider =
    Provider<MaintenanceChecklistSubmission>((ref) {
  final checklistController = ref.watch(checklistControllerProvider.notifier);
  return MaintenanceChecklistSubmission(
    submitResponses: checklistController.submitBatch,
    hasChecklistSubmitError: () =>
        ref.read(checklistControllerProvider).hasError,
    historyWriter: ref.watch(savedChecklistHistoryWriterProvider),
    preventativeMaintenanceCompletion:
        ref.watch(preventativeMaintenanceCompletionProvider),
  );
});

final operationsChecklistSubmissionProvider =
    Provider<OperationsChecklistSubmission>((ref) {
  return OperationsChecklistSubmission(
    createRun: _createOperatorChecklistRun,
    insertResponses: _insertOperatorChecklistResponses,
    historyWriter: ref.watch(savedChecklistHistoryWriterProvider),
  );
});

typedef SubmitMaintenanceResponses = Future<void> Function({
  required String workOrderId,
  required String completedBy,
  required Map<String, String?> responses,
  Map<String, String>? notes,
  Map<String, String?>? photoUrls,
  String? holdForSyncReason,
});

typedef LoadChecklistItems = Future<List<ChecklistItem>> Function();

class MaintenanceChecklistSubmission {
  const MaintenanceChecklistSubmission({
    required SubmitMaintenanceResponses submitResponses,
    required bool Function() hasChecklistSubmitError,
    required SavedChecklistHistoryWriter historyWriter,
    required PreventativeMaintenanceCompletion
        preventativeMaintenanceCompletion,
  })  : _submitResponses = submitResponses,
        _hasChecklistSubmitError = hasChecklistSubmitError,
        _historyWriter = historyWriter,
        _preventativeMaintenanceCompletion = preventativeMaintenanceCompletion;

  final SubmitMaintenanceResponses _submitResponses;
  final bool Function() _hasChecklistSubmitError;
  final SavedChecklistHistoryWriter _historyWriter;
  final PreventativeMaintenanceCompletion _preventativeMaintenanceCompletion;

  Future<void> submit({
    required String workOrderId,
    required String? assetId,
    required String? clientId,
    required ChecklistTemplate template,
    required LoadChecklistItems loadItems,
    required String completedBy,
    required String? submittedByRole,
    required DateTime submittedAt,
    required Map<String, String?> responses,
    required Map<String, String> notes,
    required Map<String, String?> photoUrls,
    required double? currentHours,
    required String? generalNotes,
    required String? holdForSyncReason,
  }) async {
    await _submitResponses(
      workOrderId: workOrderId,
      completedBy: completedBy,
      responses: responses,
      notes: notes,
      photoUrls: photoUrls,
      holdForSyncReason: holdForSyncReason,
    );

    if (_hasChecklistSubmitError() || assetId == null || clientId == null) {
      return;
    }

    final items = await loadItems();
    await _historyWriter.recordMaintenanceWorkOrderHistory(
      assetId: assetId,
      clientId: clientId,
      workOrderId: workOrderId,
      template: template,
      items: items,
      responses: responses,
      notes: notes,
      photoUrls: photoUrls,
      completedBy: completedBy,
      submittedByRole: submittedByRole,
      submittedAt: submittedAt,
      currentHours: currentHours,
      generalNotes: generalNotes,
    );
    await _preventativeMaintenanceCompletion
        .satisfyIntervalFromCompletedWorkOrder(workOrderId);
  }
}

class OperationsChecklistRunRecord {
  const OperationsChecklistRunRecord({
    required this.id,
    required this.clientId,
  });

  final String id;
  final String? clientId;
}

typedef CreateOperationsChecklistRun = Future<OperationsChecklistRunRecord>
    Function({
  required String assetId,
  required String? operatorId,
  required String templateId,
  required String runType,
  required DateTime completedAt,
});

typedef InsertOperationsChecklistResponses = Future<void> Function({
  required String runId,
  required Map<String, String?> responses,
  required Map<String, String> notes,
});

class OperationsChecklistSubmission {
  const OperationsChecklistSubmission({
    required CreateOperationsChecklistRun createRun,
    required InsertOperationsChecklistResponses insertResponses,
    required SavedChecklistHistoryWriter historyWriter,
  })  : _createRun = createRun,
        _insertResponses = insertResponses,
        _historyWriter = historyWriter;

  final CreateOperationsChecklistRun _createRun;
  final InsertOperationsChecklistResponses _insertResponses;
  final SavedChecklistHistoryWriter _historyWriter;

  Future<void> submit({
    required String assetId,
    required String? assetClientId,
    required String? operatorId,
    required String? submittedByRole,
    required String runType,
    required ChecklistTemplate template,
    required List<ChecklistItem> items,
    required Map<String, String?> responses,
    required Map<String, String> notes,
    required DateTime submittedAt,
    required double? currentHours,
    required String? generalNotes,
  }) async {
    final run = await _createRun(
      assetId: assetId,
      operatorId: operatorId,
      templateId: template.id,
      runType: runType,
      completedAt: submittedAt,
    );

    await _insertResponses(
      runId: run.id,
      responses: responses,
      notes: notes,
    );

    await _historyWriter.recordOperationsRunHistory(
      assetId: assetId,
      clientId: assetClientId ?? run.clientId ?? '',
      runId: run.id,
      runType: runType,
      template: template,
      items: items,
      responses: responses,
      notes: notes,
      completedBy: operatorId ?? '',
      submittedByRole: submittedByRole,
      submittedAt: submittedAt,
      currentHours: currentHours,
      generalNotes: generalNotes,
    );
  }
}

Future<OperationsChecklistRunRecord> _createOperatorChecklistRun({
  required String assetId,
  required String? operatorId,
  required String templateId,
  required String runType,
  required DateTime completedAt,
}) async {
  final run = await supabase
      .from('operator_checklist_runs')
      .insert({
        'asset_id': assetId,
        'operator_id': operatorId,
        'template_id': templateId,
        'run_type': runType,
        'completed_at': completedAt.toIso8601String(),
      })
      .select()
      .single()
      .timeout(const Duration(seconds: 4));

  return OperationsChecklistRunRecord(
    id: run['id'] as String,
    clientId: run['client_id'] as String?,
  );
}

Future<void> _insertOperatorChecklistResponses({
  required String runId,
  required Map<String, String?> responses,
  required Map<String, String> notes,
}) async {
  if (responses.isEmpty) return;

  final rows = responses.entries
      .where((e) => e.value != null)
      .map((e) => {
            'run_id': runId,
            'checklist_item_id': e.key,
            'result': e.value,
            'response_status': e.value,
            if (notes[e.key]?.isNotEmpty == true) 'notes': notes[e.key],
          })
      .toList();

  if (rows.isEmpty) return;

  await supabase
      .from('operator_checklist_responses')
      .insert(rows)
      .timeout(const Duration(seconds: 4));
}
