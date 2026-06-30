import 'package:intl/intl.dart';

enum ServiceRequestUrgency { normal, urgent }

enum ServiceRequestKind {
  breakdown,
  serviceMaintenance,
  safetyConcern,
  otherIssue,
}

enum ServiceRequestStatus { newRequest, resolved, declined }

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.clientId,
    this.assetId,
    required this.title,
    required this.description,
    this.requestTypeValue,
    this.contactPhoneOrWhatsapp,
    this.otherAssetName,
    this.photoUrls = const [],
    this.engineHours,
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
    this.assetLocation,
  });

  final String id;
  final String clientId;
  final String? assetId;
  final String title;
  final String description;
  final String? requestTypeValue;
  final String? contactPhoneOrWhatsapp;
  final String? otherAssetName;
  final List<String> photoUrls;
  final double? engineHours;
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
  final String? assetLocation;

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
      requestTypeValue: json['request_type'] as String?,
      contactPhoneOrWhatsapp: json['contact_phone_or_whatsapp'] as String?,
      otherAssetName: json['other_asset_name'] as String?,
      photoUrls: _photoUrlsFromJson(json['photo_urls']),
      engineHours: (json['engine_hours'] as num?)?.toDouble(),
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
      assetLocation: asset?['location'] as String?,
    );
  }

  String get assetDisplayName => assetName ?? otherAssetName ?? 'Other asset';

  ServiceRequestKind get kind =>
      _kindFromValue(requestTypeValue) ?? _kindFromTitle(title);

  String get kindLabel => kind.label;

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
        ServiceRequestStatus.resolved => 'Accepted',
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

  String? get handledLabel => handledAt == null
      ? null
      : 'Accepted ${DateFormat('MMM d, yyyy • h:mm a').format(handledAt!.toLocal())}';

  String? get workOrderLinkLabel =>
      generatedWorkOrderId == null ? null : 'Work order created';
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

List<String> _photoUrlsFromJson(dynamic value) {
  if (value is List) {
    return value.whereType<String>().where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

ServiceRequestKind? _kindFromValue(String? value) {
  switch (value) {
    case 'breakdown':
      return ServiceRequestKind.breakdown;
    case 'service_maintenance':
      return ServiceRequestKind.serviceMaintenance;
    case 'safety_concern':
      return ServiceRequestKind.safetyConcern;
    case 'other_issue':
      return ServiceRequestKind.otherIssue;
  }
  return null;
}

ServiceRequestKind _kindFromTitle(String value) {
  switch (value.trim().toLowerCase()) {
    case 'breakdown':
      return ServiceRequestKind.breakdown;
    case 'service / maintenance':
      return ServiceRequestKind.serviceMaintenance;
    case 'safety concern':
      return ServiceRequestKind.safetyConcern;
    default:
      return ServiceRequestKind.otherIssue;
  }
}

extension ServiceRequestKindLabel on ServiceRequestKind {
  String get label => switch (this) {
        ServiceRequestKind.breakdown => 'Breakdown',
        ServiceRequestKind.serviceMaintenance => 'Service / maintenance',
        ServiceRequestKind.safetyConcern => 'Safety concern',
        ServiceRequestKind.otherIssue => 'Other issue',
      };
}
