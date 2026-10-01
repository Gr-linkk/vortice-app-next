import '../lab_store.dart';
import '../model.dart';

/// The canonical scope of one experimental office authority. It is public
/// identity, never a capability. Coherent recovery preserves the company and
/// office-device IDs; access sidecars are deliberately excluded from recovery.
class AgentAccessScope {
  const AgentAccessScope({
    required this.workspaceId,
    required this.companyId,
    required this.deviceId,
  });

  final String workspaceId, companyId, deviceId;

  static AgentAccessScope? forOffice(LabStore store) {
    if (!store.office || !store.realWorkspace) return null;
    final company = store.catalog!['companyId'] as String;
    final device = store.device;
    final workspace = 'ws-${contentHash({
      'application': 'org.vortice.next.maintenance_local',
      'company_id': company,
      'office_device_id': device,
    })}';
    return AgentAccessScope(
      workspaceId: workspace,
      companyId: company,
      deviceId: device,
    );
  }

  Json toJson() => {
    'workspace_id': workspaceId,
    'company_id': companyId,
    'device_id': deviceId,
  };
}
