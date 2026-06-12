import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/operator/operator_checklist_status_button.dart';
import 'package:vortice_app/models/checklist_item.dart';

class OperatorChecklistQuickCheckItem extends StatefulWidget {
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
    final file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file != null) widget.onPhotoChanged(await file.readAsBytes());
  }

  Future<void> _takePhoto() async {
    final file =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (file != null) widget.onPhotoChanged(await file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.response;
    final showDetail =
        status == 'alert' || status == 'monitor' || status == 'action';

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
                  color: AppColors.success,
                  onTap: () => widget
                      .onChanged(status == 'pass' ? null : 'pass'),
                ),
                const SizedBox(width: 6),
                OperatorChecklistStatusButton(
                  label: 'MONITOR',
                  value: 'monitor',
                  current: status,
                  color: AppColors.warning,
                  onTap: () => widget.onChanged(
                    status == 'monitor' || status == 'alert' ? null : 'monitor',
                  ),
                ),
                const SizedBox(width: 6),
                OperatorChecklistStatusButton(
                  label: 'ACTION',
                  value: 'action',
                  current: status,
                  color: AppColors.error,
                  onTap: () => widget
                      .onChanged(status == 'action' ? null : 'action'),
                ),
                const SizedBox(width: 6),
                OperatorChecklistStatusButton(
                  label: 'N/A',
                  value: 'n/a',
                  current: status,
                  color: AppColors.textSecondary,
                  onTap: () =>
                      widget.onChanged(status == 'n/a' ? null : 'n/a'),
                ),
              ],
            ),
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
                          decoration: const InputDecoration(
                            hintText: 'Describe issue / action',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
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
                                icon: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AppColors.error,
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
