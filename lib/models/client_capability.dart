/// Optional per-client service capabilities controlled by the Vórtice owner.
///
/// Baseline client portal behavior is intentionally not represented here:
/// assets/documents/history, invoices, and service requests are always-on app
/// capabilities rather than switchboard rows.
enum ClientCapability {
  operationalChecklists(
    key: 'operational_checklists',
    label: 'Operational Checklists',
    description: 'Pre-op, daily, captain/operator checklist workflows.',
  ),
  pmChecklists(
    key: 'pm_checklists',
    label: 'PM / Mechanic Checklists',
    description: 'Preventive-maintenance and inspection checklist workflows.',
  ),
  pmPartsLists(
    key: 'pm_parts_lists',
    label: 'PM Parts Lists',
    description: 'Parts guidance tied to assets and preventive maintenance.',
  ),
  maintenancePlanning(
    key: 'maintenance_planning',
    label: 'Maintenance Planning',
    description: 'Schedules, service intervals, and upcoming preventive work.',
  ),
  telemetry(
    key: 'telemetry',
    label: 'Telemetry',
    description: 'Telemetry UI and data access for enabled client fleets.',
  );

  const ClientCapability({
    required this.key,
    required this.label,
    required this.description,
  });

  final String key;
  final String label;
  final String description;

  static ClientCapability? tryFromKey(String key) {
    for (final capability in values) {
      if (capability.key == key) return capability;
    }
    return null;
  }
}

class ClientCapabilitySwitchboard {
  ClientCapabilitySwitchboard({
    required this.clientId,
    Map<ClientCapability, bool>? enabledByCapability,
  }) : enabledByCapability = {
          for (final capability in ClientCapability.values)
            capability: enabledByCapability?[capability] ?? false,
        };

  final String clientId;
  final Map<ClientCapability, bool> enabledByCapability;

  bool isEnabled(ClientCapability capability) =>
      enabledByCapability[capability] ?? false;

  static ClientCapabilitySwitchboard disabled(String clientId) =>
      ClientCapabilitySwitchboard(clientId: clientId);
}
