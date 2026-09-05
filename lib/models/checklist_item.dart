import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_item.freezed.dart';
part 'checklist_item.g.dart';

@freezed
abstract class ChecklistItem with _$ChecklistItem {
  const factory ChecklistItem({
    required String id,
    @JsonKey(name: 'template_id') required String templateId,
    @JsonKey(name: 'description_en') required String descriptionEn,
    @JsonKey(name: 'description_es') String? descriptionEs,
    String? category,
    @JsonKey(name: 'requires_photo') @Default(false) bool requiresPhoto,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _ChecklistItem;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => _$ChecklistItemFromJson(json);
}
