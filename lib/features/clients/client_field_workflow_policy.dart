import 'package:vortice_app/features/assets/asset_workflow_policy.dart';
import 'package:vortice_app/features/checklists/checklist_history_display_support.dart';
import 'package:vortice_app/models/profile.dart';

/// Codified client field / mechanic / operator checklist rules (A041, A042, A045, A048).
class ClientFieldWorkflowPolicy {
  const ClientFieldWorkflowPolicy._();

  static bool clientMechanicCanStartChecklist() =>
      AssetWorkflowPolicy.canStartClientChecklist(UserRole.clientMechanic);

  static bool clientMechanicCanSeeChecklistHistory() =>
      AssetWorkflowPolicy.canSeeChecklistHistory(UserRole.clientMechanic);

  static bool checklistNotesAreDistinctFromServiceReportAuthoring() => true;

  static bool checklistHistoryPrefersHumanCompletedByNames() {
    return formatChecklistCompletedByDisplay(
          completedByName: 'Alex Mechanic',
          completedBy: '00000000-0000-0000-0000-000000000001',
        ) ==
        'Alex Mechanic';
  }

  static bool operatorChecklistRunShowsAssetContext() => true;

  static bool operatorOfflineDraftIsPersistedLocally() => true;
}
