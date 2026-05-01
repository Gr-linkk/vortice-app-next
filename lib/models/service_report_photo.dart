import 'package:freezed_annotation/freezed_annotation.dart';

part 'service_report_photo.freezed.dart';
part 'service_report_photo.g.dart';

@freezed
class ServiceReportPhoto with _$ServiceReportPhoto {
  const factory ServiceReportPhoto({
    required String id,
    @JsonKey(name: 'service_report_id') required String serviceReportId,
    @JsonKey(name: 'photo_url') required String photoUrl,
    String? caption,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @JsonKey(name: 'uploaded_by') String? uploadedBy,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ServiceReportPhoto;

  factory ServiceReportPhoto.fromJson(Map<String, dynamic> json) =>
      _$ServiceReportPhotoFromJson(json);
}
