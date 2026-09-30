import 'dart:convert';

/// One immutable attempt to save or submit a report. A retry keeps its original
/// revision and input even if the current screen or server data has changed.
class ReportCommand {
  ReportCommand({
    required this.id,
    required this.revision,
    required this.action,
    required Map<String, dynamic> data,
  }) : _encodedData = jsonEncode(data);

  final String id, action;
  final int revision;
  final String _encodedData;

  // Callers receive a copy; neither UI edits nor transport code can change the
  // command retained for an exact retry.
  Map<String, dynamic> get data =>
      jsonDecode(_encodedData) as Map<String, dynamic>;

  factory ReportCommand.fromJson(Map<String, dynamic> json) => ReportCommand(
    id: json['id'] as String,
    revision: (json['revision'] as num).toInt(),
    action: json['action'] as String,
    data: Map<String, dynamic>.from(json['data'] as Map),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'revision': revision,
    'action': action,
    'data': data,
  };
}
