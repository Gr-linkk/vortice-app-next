import 'package:intl/intl.dart';

enum ServiceRequestUrgency { normal, urgent }

enum ServiceRequestStatus { newRequest, resolved, declined }

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.clientId,
    this.assetId,
    required this.title,
    required this.description,
    required this.urgency,
    required this.status,
    this.sourceMaintenanceRequestId,
    this.generatedWorkOrderId,
    this.createdAt,
    this.updatedAt,
    this.handledAt,
    this.handledBy,
    this.clientName,
    this.assetName,
  });

  final String id;
  final String clientId;
  final String? assetId;
  final String title;
  final String description;
  final ServiceRequestUrgency urgency;
  final ServiceRequestStatus status;
  final String? sourceMaintenanceRequestId;
  final String? generatedWorkOrderId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? handledAt;
  final String? handledBy;
  final String? clientName;
  final String? assetName;

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    final client = json['client'] is Map<String, dynamic>
        ? json['client'] as Map<String, dynamic>
        : json['profiles'] is Map<String, dynamic>
            ? json['profiles'] as Map<String, dynamic>
            : null;
    final asset = json['asset'] is Map<String, dynamic>
        ? json['asset'] as Map<String, dynamic>
        : json['assets'] is Map<String, dynamic>
            ? json['assets'] as Map<String, dynamic>
            : null;

    return ServiceRequest(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      assetId: json['asset_id'] as String?,
      title: json['title'] as String? ?? 'Service request',
      description: json['description'] as String? ?? '',
      urgency: _urgencyFromJson(json['urgency']),
      status: _statusFromJson(json['status']),
      sourceMaintenanceRequestId:
          json['source_maintenance_request_id'] as String?,
      generatedWorkOrderId: json['generated_work_order_id'] as String?,
      createdAt: _dateFromJson(json['created_at']),
      updatedAt: _dateFromJson(json['updated_at']),
      handledAt: _dateFromJson(json['handled_at']),
      handledBy: json['handled_by'] as String?,
      clientName:
          client?['full_name'] as String? ?? client?['email'] as String?,
      assetName: asset?['name'] as String?,
    );
  }

  String get urgencyValue => switch (urgency) {
        ServiceRequestUrgency.normal => 'normal',
        ServiceRequestUrgency.urgent => 'urgent',
      };

  String get statusValue => switch (status) {
        ServiceRequestStatus.newRequest => 'new',
        ServiceRequestStatus.resolved => 'resolved',
        ServiceRequestStatus.declined => 'declined',
      };

  String get clientStatusLabel => switch (status) {
        ServiceRequestStatus.newRequest => 'Sent',
        ServiceRequestStatus.resolved => 'Being handled',
        ServiceRequestStatus.declined => 'Declined',
      };

  String get staffStatusLabel => switch (status) {
        ServiceRequestStatus.newRequest => 'New',
        ServiceRequestStatus.resolved => 'Resolved',
        ServiceRequestStatus.declined => 'Declined',
      };

  String get createdLabel => createdAt == null
      ? '—'
      : DateFormat('MMM d, yyyy • h:mm a').format(createdAt!.toLocal());
}

ServiceRequestUrgency _urgencyFromJson(dynamic value) {
  return value == 'urgent'
      ? ServiceRequestUrgency.urgent
      : ServiceRequestUrgency.normal;
}

ServiceRequestStatus _statusFromJson(dynamic value) {
  return switch (value) {
    'resolved' => ServiceRequestStatus.resolved,
    'declined' => ServiceRequestStatus.declined,
    _ => ServiceRequestStatus.newRequest,
  };
}

DateTime? _dateFromJson(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
