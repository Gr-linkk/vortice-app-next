import 'package:freezed_annotation/freezed_annotation.dart';

part 'imported_doc.freezed.dart';
part 'imported_doc.g.dart';

@freezed
class ImportedDoc with _$ImportedDoc {
  const factory ImportedDoc({
    required String id,
    @JsonKey(name: 'file_name') required String fileName,
    @JsonKey(name: 'file_url') String? fileUrl,
    @JsonKey(name: 'doc_type') String? docType,
    @JsonKey(name: 'source_language') String? sourceLanguage,
    @JsonKey(name: 'processed') @Default(false) bool processed,
    @JsonKey(name: 'extracted_data') Map<String, dynamic>? extractedData,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _ImportedDoc;

  factory ImportedDoc.fromJson(Map<String, dynamic> json) =>
      _$ImportedDocFromJson(json);
}
