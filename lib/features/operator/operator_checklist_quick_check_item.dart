import 'dart:typed_data';
import 'operator_issue_details.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/operator/operator_checklist_status_button.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';

class OperatorChecklistQuickCheckItem extends StatefulWidget {
  final Map<String, dynamic> issue;
  final ValueChanged<Map<String, dynamic>>? onIssueChanged;
  final ChecklistItem item;
  final String? response;
  final String note;
  final Uint8List? photo;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<Uint8List?> onPhotoChanged;

  const OperatorChecklistQuickCheckItem({
    super.key,
    required this.item,
    this.issue = const {},
    this.onIssueChanged,
    required this.response,
    required this.note,
    required this.photo,
    required this.onChanged,
    required this.onNoteChanged,
    required this.onPhotoChanged,
  });

  @override
  State<OperatorChecklistQuickCheckItem> createState() =>
      _OperatorChecklistQuickCheckItemState();
}

class _OperatorChecklistQuickCheckItemState
    extends State<OperatorChecklistQuickCheckItem> {
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _noteCtrl.text = widget.note;
  }

  @override
  void didUpdateWidget(covariant OperatorChecklistQuickCheckItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note != widget.note && _noteCtrl.text != widget.note) {
      _noteCtrl.text = widget.note;
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (file != null) widget.onPhotoChanged(await file.readAsBytes());
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (file != null) widget.onPhotoChanged(await file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.response;
    final issueDetails =
        ['monitor', 'alert', 'action'].contains(status) &&
            widget.onIssueChanged != null
        ? OperatorIssueDetails(
            value: widget.issue,
            onChanged: widget.onIssueChanged!,
            critical: widget.item.definition['critical'] == true,
            separateMessage:
                checklistInputType(widget.item.definition) != 'check',
          )
        : const SizedBox.shrink();
    if (widget.item.definition.isNotEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChecklistAnswerFields(
                item: widget.item.toJson(),
                result: status,
                value: widget.note,
                onResult: widget.onChanged,
                onValue: widget.onNoteChanged,
              ),
              if (widget.photo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Image.memory(
                        widget.photo!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                      IconButton(
                        onPressed: () => widget.onPhotoChanged(null),
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove photo',
                      ),
                    ],
                  ),
                ),
              issueDetails,
              ChecklistEvidenceActions(
                requiredPhoto: widget.item.requiresPhoto,
                onGallery: _pickPhoto,
                onCamera: _takePhoto,
              ),
            ],
          ),
        ),
      );
    }
    final showDetail =
        status == 'alert' ||
        status == 'monitor' ||
        status == 'action' ||
        widget.item.requiresPhoto;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.descriptionEn,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OperatorChecklistStatusButton(
                  label: 'PASS',
                  value: 'pass',
                  current: status,
                  color: context.appColors.success,
                  onTap: () =>
                      widget.onChanged(status == 'pass' ? null : 'pass'),
                ),
                const SizedBox(width: 6),
                OperatorChecklistStatusButton(
                  label: 'MONITOR',
                  value: 'monitor',
                  current: status,
                  color: context.appColors.warning,
                  onTap: () => widget.onChanged(
                    status == 'monitor' || status == 'alert' ? null : 'monitor',
                  ),
                ),
                const SizedBox(width: 6),
                OperatorChecklistStatusButton(
                  label: 'ACTION',
                  value: 'action',
                  current: status,
                  color: context.appColors.error,
                  onTap: () =>
                      widget.onChanged(status == 'action' ? null : 'action'),
                ),
                const SizedBox(width: 6),
                OperatorChecklistStatusButton(
                  label: 'N/A',
                  value: 'n/a',
                  current: status,
                  color: context.appColors.textSecondary,
                  onTap: () => widget.onChanged(status == 'n/a' ? null : 'n/a'),
                ),
              ],
            ),
            issueDetails,
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: showDetail
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteCtrl,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Describe issue / action',
                            hintStyle: TextStyle(
                              color: context.appColors.textSecondary,
                              fontSize: 12,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          onChanged: widget.onNoteChanged,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (widget.photo != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.memory(
                                  widget.photo!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: context.appColors.error,
                                ),
                                onPressed: () => widget.onPhotoChanged(null),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 4),
                            ],
                            OutlinedButton.icon(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.photo_library, size: 14),
                              label: const Text(
                                'Photo',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt, size: 14),
                              label: const Text(
                                'Camera',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
