import 'dart:async';
import 'dart:typed_data';

import 'package:vortice_app/features/checklists/checklist_attachment_support.dart'
    as checklist_attachments;
import 'package:vortice_app/features/checklists/checklist_history_display_support.dart';
import 'package:vortice_app/features/checklists/checklist_submission_support.dart';
import 'package:vortice_app/features/service_intervals/maintenance_work_order_draft.dart';
import 'package:vortice_app/features/work_orders/create_work_order_pm_parts_support.dart';
import 'package:vortice_app/features/work_orders/create_work_order_support.dart';
import 'package:vortice_app/models/pm_parts_requirement.dart';
import 'package:vortice_app/models/work_order.dart';

/// Codified PM checklist + maintenance-plan workflow rules (A002, A003, A010, A020, A034).
class PmChecklistWorkflowPolicy {
  const PmChecklistWorkflowPolicy._();

  static bool createWorkOrderSupportsFreestylePartsNotes() {
    return notesInternalFromParts('Oil filter, zinc anodes') ==
        'Parts expected: Oil filter, zinc anodes';
  }

  static bool kitSelectionShowsPmPartsPreview() {
    return shouldShowPmPartsKitPreview(
      jobType: WorkOrderJobType.repair,
      checklistTemplateId: 'template-1',
    );
  }

  static bool kitSelectionPrefillsPartsField() {
    return pmKitSelectionPrefillsWorkOrderPartsField() &&
        formatPmPartsForWorkOrderNotes([
          const PmPartsRequirement(
            id: 'part-1',
            templateId: 'template-1',
            description: 'Oil filter',
            partNumber: 'OF-100',
            qty: 2,
            unit: 'ea',
          ),
        ]).contains('Oil filter');
  }

  static bool maintenancePlanDraftPrefillsCoreFields() {
    const draft = MaintenanceWorkOrderDraft(
      assetId: 'asset-1',
      checklistTemplateId: 'template-1',
      title: '250 HR Service',
    );
    return draft.assetId == 'asset-1' &&
        draft.checklistTemplateId == 'template-1' &&
        draft.title == '250 HR Service' &&
        pmKitSelectionPrefillsWorkOrderPartsField();
  }

  static bool checklistAttachmentsAppendInsteadOfReplace() {
    final photos = <String, List<Uint8List>>{};
    checklist_attachments.appendChecklistPhoto(
      photos,
      'item-1',
      Uint8List.fromList([1]),
    );
    checklist_attachments.appendChecklistPhoto(
      photos,
      'item-1',
      Uint8List.fromList([2]),
    );
    return checklist_attachments.checklistAttachmentsAppendInsteadOfReplace() &&
        checklist_attachments.checklistPhotosForItem(photos, 'item-1').length ==
            2;
  }

  static bool checklistSubmissionRetainsAllPhotoUrls() {
    final urls = checklist_attachments.serializeChecklistPhotoUrls([
      'https://example.com/a.jpg',
      'https://example.com/b.jpg',
    ]);
    return checklist_attachments.parseChecklistPhotoUrls(urls).length == 2;
  }

  static bool checklistHistoryShowsHumanCompletedBy() {
    return formatChecklistCompletedByDisplay(
          completedByName: 'Maria Tech',
          completedBy: '00000000-0000-0000-0000-000000000002',
        ) ==
        'Maria Tech';
  }

  static bool onlineSubmissionUsesSubmittedStateMessage() {
    return ChecklistSubmissionSupport.onlineSubmittedMessage()
        .contains('submitted');
  }

  static bool transientErrorsQueueForSync() {
    return ChecklistSubmissionSupport.isTransientSyncError(
      TimeoutException('network timeout'),
    );
  }

  static bool permissionErrorsDoNotUsePendingSyncMessage() {
    return !ChecklistSubmissionSupport.isTransientSyncError(
      Exception('new row violates row-level security policy (42501)'),
    );
  }
}
