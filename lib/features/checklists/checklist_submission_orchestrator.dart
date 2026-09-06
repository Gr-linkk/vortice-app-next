import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/sync/field_work_queue.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/saved_checklist_history_writer.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

final maintenanceChecklistSubmissionProvider =
    Provider<MaintenanceChecklistSubmission>((ref) {
      final checklistController = ref.watch(
        checklistControllerProvider.notifier,
      );
      return MaintenanceChecklistSubmission(
        submitResponses: checklistController.submitBatch,
        hasChecklistSubmitError: () =>
            ref.read(checklistControllerProvider).hasError,
        historyWriter: ref.watch(savedChecklistHistoryWriterProvider),
      );
    });

final operationsChecklistSubmissionProvider =
    Provider<OperationsChecklistSubmission>((ref) {
      return OperationsChecklistSubmission(
        atomicSubmit: (id, data, photos) async {
          final queue = ref.read(fieldWorkQueueProvider);
          if (queue == null) {
            throw StateError('Sign in before saving a checklist');
          }
          final paths = <String, String>{};
          await queue.db.transaction(() async {
            for (final entry in photos.entries) {
              final bytes = entry.value;
              if (bytes == null) continue;
              final ext = bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80
                  ? 'png'
                  : bytes.length > 12 && bytes[0] == 82 && bytes[8] == 87
                  ? 'webp'
                  : 'jpg';
              final path =
                  '${data['asset_id']}/${queue.account}/$id/${entry.key}.$ext';
              paths[entry.key] = path;
              await queue.enqueue(
                FieldOperation(
                  id: 'photo:$path',
                  kind: 'upload',
                  subject: id,
                  payload: {
                    'bucket': 'operator-evidence',
                    'path': path,
                    'bytes': base64Encode(bytes),
                    'contentType': ext == 'jpg' ? 'image/jpeg' : 'image/$ext',
                  },
                ),
              );
            }
            await queue.enqueue(
              FieldOperation(
                id: id,
                kind: 'submit_operations_checklist',
                subject: id,
                payload: {
                  'p_operation': id,
                  'p_data': {...data, 'photos': paths},
                },
              ),
            );
          });
          await queue.flush();
        },
        createRun: _createOperatorChecklistRun,
        insertResponses: _insertOperatorChecklistResponses,
        historyWriter: ref.watch(savedChecklistHistoryWriterProvider),
      );
    });

final clientChecklistSubmissionProvider = Provider<ClientChecklistSubmission>(
  (ref) => ClientChecklistSubmission(
    historyWriter: ref.watch(savedChecklistHistoryWriterProvider),
  ),
);

typedef SubmitMaintenanceResponses =
    Future<void> Function({
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
  }) : _submitResponses = submitResponses,
       _hasChecklistSubmitError = hasChecklistSubmitError,
       _historyWriter = historyWriter;

  final SubmitMaintenanceResponses _submitResponses;
  final bool Function() _hasChecklistSubmitError;
  final SavedChecklistHistoryWriter _historyWriter;

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
    // Checklist submission records inspection evidence only. NOW-006 applies
    // service completion atomically after manager approval of an explicit plan.
  }
}

class ClientChecklistSubmission {
  const ClientChecklistSubmission({
    required SavedChecklistHistoryWriter historyWriter,
  }) : _historyWriter = historyWriter;

  final SavedChecklistHistoryWriter _historyWriter;

  Future<void> submit({
    required String assetId,
    required String clientId,
    required String submittedBy,
    required String? submittedByRole,
    required ChecklistTemplate template,
    required List<ChecklistItem> items,
    required Map<String, String?> responses,
    required Map<String, String> notes,
    required Map<String, String?> photoUrls,
    required DateTime submittedAt,
    required double? currentHours,
    required String? generalNotes,
  }) {
    return _historyWriter.recordClientSubmittedHistory(
      assetId: assetId,
      clientId: clientId,
      template: template,
      items: items,
      responses: responses,
      notes: notes,
      photoUrls: photoUrls,
      completedBy: submittedBy,
      submittedByRole: submittedByRole,
      submittedAt: submittedAt,
      currentHours: currentHours,
      generalNotes: generalNotes,
    );
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

typedef CreateOperationsChecklistRun =
    Future<OperationsChecklistRunRecord> Function({
      required String assetId,
      required String? operatorId,
      required String templateId,
      required String runType,
      required DateTime completedAt,
    });

typedef InsertOperationsChecklistResponses =
    Future<void> Function({
      required String runId,
      required Map<String, String?> responses,
      required Map<String, String> notes,
    });

class OperationsChecklistSubmission {
  const OperationsChecklistSubmission({
    this.atomicSubmit,
    required CreateOperationsChecklistRun createRun,
    required InsertOperationsChecklistResponses insertResponses,
    required SavedChecklistHistoryWriter historyWriter,
  }) : _createRun = createRun,
       _insertResponses = insertResponses,
       _historyWriter = historyWriter;

  final CreateOperationsChecklistRun _createRun;
  final Future<void> Function(
    String,
    Map<String, dynamic>,
    Map<String, Uint8List?>,
  )?
  atomicSubmit;
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
    String? operationId,
    Map<String, Uint8List?> photos = const {},
  }) async {
    validateOperationsChecklist(
      items,
      responses,
      notes,
      currentHours,
      photos: photos,
    );
    if (atomicSubmit != null) {
      await atomicSubmit!(operationId ?? const Uuid().v4(), {
        'asset_id': assetId,
        'template_id': template.id,
        'template_version': template.version,
        'run_type': runType,
        'completed_at': submittedAt.toUtc().toIso8601String(),
        'responses': responses,
        'notes': notes,
        'current_hours': currentHours,
        'general_notes': generalNotes,
      }, photos);
      return;
    }
    final run = await _createRun(
      assetId: assetId,
      operatorId: operatorId,
      templateId: template.id,
      runType: runType,
      completedAt: submittedAt,
    );

    await _insertResponses(runId: run.id, responses: responses, notes: notes);

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

void validateOperationsChecklist(
  List<ChecklistItem> items,
  Map<String, String?> responses,
  Map<String, String> notes,
  double? currentHours, {
  Map<String, Uint8List?> photos = const {},
}) {
  if (items.isEmpty ||
      items.any(
        (item) => !const {
          'pass',
          'monitor',
          'alert',
          'action',
          'n/a',
        }.contains(responses[item.id]),
      )) {
    throw const OperationsChecklistValidationException('answers');
  }
  if (responses.keys.any((id) => !items.any((item) => item.id == id))) {
    throw const OperationsChecklistValidationException('answers');
  }
  if (items.any(
    (item) => item.requiresPhoto && (photos[item.id]?.isEmpty ?? true),
  )) {
    throw const OperationsChecklistValidationException('photos');
  }
  if (items.any(
    (item) =>
        const {'monitor', 'alert', 'action'}.contains(responses[item.id]) &&
        (notes[item.id]?.trim().isEmpty ?? true),
  )) {
    throw const OperationsChecklistValidationException('notes');
  }
  if (currentHours != null && (!currentHours.isFinite || currentHours < 0)) {
    throw const OperationsChecklistValidationException('hours');
  }
}

class OperationsChecklistValidationException implements Exception {
  const OperationsChecklistValidationException(this.reason);

  final String reason;

  String message(bool es) => switch (reason) {
    'photos' =>
      es
          ? 'Añade las fotos requeridas antes de guardar. El borrador se conserva.'
          : 'Add the required photos before saving. Your draft is retained.',
    'notes' =>
      es
          ? 'Agrega una nota a los elementos de seguimiento o acción.'
          : 'Add a note to each Monitor or Action item.',
    'hours' =>
      es
          ? 'Ingresa horas válidas, iguales o mayores que cero.'
          : 'Enter valid hours of zero or more.',
    _ =>
      es
          ? 'Responde todos los elementos antes de completar la lista.'
          : 'Answer every item before completing the checklist.',
  };
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
        'completed_at': completedAt.toUtc().toIso8601String(),
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
      .map(
        (e) => {
          'run_id': runId,
          'checklist_item_id': e.key,
          ...operationsResponseStorageValues(e.value!),
          if (notes[e.key]?.isNotEmpty == true) 'notes': notes[e.key],
        },
      )
      .toList();

  if (rows.isEmpty) return;

  await supabase
      .from('operator_checklist_responses')
      .insert(rows)
      .timeout(const Duration(seconds: 4));
}

Map<String, String?> operationsResponseStorageValues(String response) => {
  'result': switch (response) {
    'pass' => 'good',
    'n/a' => 'not_applicable',
    'monitor' || 'alert' || 'action' => 'needs_attention',
    _ => throw ArgumentError.value(response, 'response'),
  },
  'response_status': switch (response) {
    'monitor' => 'alert',
    'n/a' => null,
    _ => response,
  },
};
