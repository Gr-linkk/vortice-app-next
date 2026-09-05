enum OperatingState {
  unknown('unknown'),
  available('available'),
  restricted('restricted'),
  outOfService('out_of_service'),
  underMaintenance('under_maintenance');

  const OperatingState(this.value);
  final String value;
  bool get isDowntime => this == outOfService || this == underMaintenance;

  static OperatingState parse(String? value) =>
      values.firstWhere((state) => state.value == value, orElse: () => unknown);

  String label(bool es) => switch (this) {
    unknown => es ? 'Sin evaluar' : 'Not assessed',
    available => es ? 'Disponible' : 'Available',
    restricted => es ? 'Uso restringido' : 'Restricted use',
    outOfService => es ? 'Fuera de servicio' : 'Out of service',
    underMaintenance => es ? 'En mantenimiento' : 'Under maintenance',
  };
}

enum FaultStatus {
  open('open'),
  acknowledged('acknowledged'),
  inProgress('in_progress'),
  pendingReview('pending_review'),
  resolved('resolved'),
  dismissed('dismissed'),
  unknown('unknown');

  const FaultStatus(this.value);
  final String value;
  bool get isActive => this != resolved && this != dismissed;
  static FaultStatus parse(String? value) => value == 'converted'
      ? acknowledged
      : values.firstWhere((s) => s.value == value, orElse: () => unknown);
  String label(bool es) => switch (this) {
    open => es ? 'Reportada' : 'Reported',
    acknowledged => es ? 'Aceptada' : 'Acknowledged',
    inProgress => es ? 'En reparación' : 'In repair',
    pendingReview => es ? 'Pendiente de revisión' : 'Awaiting review',
    resolved => es ? 'Resuelta' : 'Resolved',
    dismissed => es ? 'Descartada' : 'Dismissed',
    unknown => es ? 'Estado desconocido' : 'Unknown status',
  };
}

DateTime? _date(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

class FleetAsset {
  const FleetAsset({
    required this.id,
    required this.name,
    this.location,
    this.state = OperatingState.unknown,
    this.reason,
    this.changedAt,
    this.changedByName,
    this.unavailableSince,
    this.downtimeSeconds = 0,
    this.revision = 0,
    this.openFaults = 0,
    this.urgentFaults = 0,
  });
  final String id;
  final String name;
  final String? location;
  final OperatingState state;
  final String? reason;
  final DateTime? changedAt;
  final String? changedByName;
  final DateTime? unavailableSince;
  final int downtimeSeconds;
  final int revision;
  final int openFaults;
  final int urgentFaults;

  factory FleetAsset.fromJson(Map<String, dynamic> json) => FleetAsset(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Asset',
    location: json['location'] as String?,
    state: OperatingState.parse(json['operating_state'] as String?),
    reason: json['reason'] as String?,
    changedAt: _date(json['changed_at']),
    changedByName: json['changed_by_name'] as String?,
    unavailableSince: _date(json['unavailable_since']),
    downtimeSeconds: (json['downtime_seconds'] as num?)?.toInt() ?? 0,
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    openFaults: (json['open_faults'] as num?)?.toInt() ?? 0,
    urgentFaults: (json['urgent_faults'] as num?)?.toInt() ?? 0,
  );

  Duration totalDowntime(DateTime now) {
    final current = state.isDowntime && unavailableSince != null
        ? now.difference(unavailableSince!)
        : Duration.zero;
    return Duration(seconds: downtimeSeconds) +
        (current.isNegative ? Duration.zero : current);
  }
}

class FleetFault {
  const FleetFault({
    required this.id,
    required this.assetId,
    required this.description,
    this.assetName = '',
    this.status = FaultStatus.open,
    this.urgent = false,
    this.assignedTo,
    this.assigneeName,
    this.reporterName,
    this.workOrderId,
    this.workOrderStatus,
    this.createdAt,
    this.updatedAt,
    this.resolutionNote,
    this.revision = 0,
  });
  final String id;
  final String assetId;
  final String assetName;
  final String description;
  final FaultStatus status;
  final bool urgent;
  final String? assignedTo;
  final String? assigneeName;
  final String? reporterName;
  final String? workOrderId;
  final String? workOrderStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? resolutionNote;
  final int revision;

  factory FleetFault.fromJson(Map<String, dynamic> json) => FleetFault(
    id: json['id'] as String,
    assetId: json['asset_id'] as String,
    assetName: json['asset_name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    status: FaultStatus.parse(json['status'] as String?),
    urgent: json['severity'] == 'urgent',
    assignedTo: json['assigned_to'] as String?,
    assigneeName: json['assignee_name'] as String?,
    reporterName: json['reporter_name'] as String?,
    workOrderId: json['converted_to_work_order_id'] as String?,
    workOrderStatus: json['work_order_status'] as String?,
    createdAt: _date(json['created_at']),
    updatedAt: _date(json['updated_at']),
    resolutionNote: json['resolution_note'] as String?,
    revision: (json['revision'] as num?)?.toInt() ?? 0,
  );
}

class FleetEvent {
  const FleetEvent({
    required this.id,
    required this.kind,
    required this.note,
    required this.actorName,
    this.fromState,
    this.toState,
    this.createdAt,
  });
  final String id;
  final String kind;
  final String note;
  final String actorName;
  final String? fromState;
  final String? toState;
  final DateTime? createdAt;
  factory FleetEvent.fromJson(Map<String, dynamic> json) => FleetEvent(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? 'availability',
    note: json['note'] as String? ?? '',
    actorName: json['actor_name'] as String? ?? '',
    fromState: json['from_state'] as String?,
    toState: json['to_state'] as String?,
    createdAt: _date(json['created_at']),
  );
}

class FleetMember {
  const FleetMember({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final String role;
  factory FleetMember.fromJson(Map<String, dynamic> json) => FleetMember(
    id: json['id'] as String,
    name: json['full_name'] as String? ?? '',
    role: json['role'] as String? ?? '',
  );
}
