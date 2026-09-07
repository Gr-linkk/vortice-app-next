import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/features/checklists/checklist_sync_banner.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/features/checklists/checklist_answer_fields.dart';
import 'package:vortice_app/features/service_reports/service_report_media.dart';

class ChecklistItemWidget extends StatefulWidget {
  final ChecklistItem item;
  final String? status;
  final String note;
  final List<Uint8List> localPhotos;
  final List<String> uploadedPhotoUrls;
  final String? syncStatus;
  final void Function(String? v) onStatusChanged;
  final void Function(String v) onNoteChanged;
  final void Function(Uint8List bytes) onPhotoAppended;
  final void Function(int index) onLocalPhotoRemoved;
  final void Function(int index) onUploadedPhotoRemoved;

  const ChecklistItemWidget({
    super.key,
    required this.item,
    required this.status,
    required this.note,
    required this.localPhotos,
    required this.uploadedPhotoUrls,
    required this.syncStatus,
    required this.onStatusChanged,
    required this.onNoteChanged,
    required this.onPhotoAppended,
    required this.onLocalPhotoRemoved,
    required this.onUploadedPhotoRemoved,
  });

  @override
  State<ChecklistItemWidget> createState() => _ChecklistItemWidgetState();
}

class _ChecklistItemWidgetState extends State<ChecklistItemWidget> {
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _noteCtrl.text = widget.note;
  }

  @override
  void didUpdateWidget(covariant ChecklistItemWidget oldWidget) {
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
    if (file != null) {
      final bytes = await file.readAsBytes();
      widget.onPhotoAppended(bytes);
    }
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      widget.onPhotoAppended(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
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
                onResult: widget.onStatusChanged,
                onValue: widget.onNoteChanged,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < widget.uploadedPhotoUrls.length; i++)
                    _ChecklistPhotoTile(
                      child: ChecklistPhotoPreview(
                        photo: null,
                        photoUrl: widget.uploadedPhotoUrls[i],
                      ),
                      onRemove: () => widget.onUploadedPhotoRemoved(i),
                    ),
                  for (var i = 0; i < widget.localPhotos.length; i++)
                    _ChecklistPhotoTile(
                      child: ChecklistPhotoPreview(
                        photo: widget.localPhotos[i],
                        photoUrl: null,
                      ),
                      onRemove: () => widget.onLocalPhotoRemoved(i),
                    ),
                ],
              ),
              ChecklistEvidenceActions(
                requiredPhoto: widget.item.requiresPhoto,
                onGallery: _pickPhoto,
                onCamera: _takePhoto,
              ),
              if (syncStatusChipLabel(widget.syncStatus) != null)
                ChecklistItemSyncChip(syncStatus: widget.syncStatus!),
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
    final hasPhotos =
        widget.localPhotos.isNotEmpty || widget.uploadedPhotoUrls.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.item.descriptionEn,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (syncStatusChipLabel(widget.syncStatus) != null) ...[
                  const SizedBox(width: 8),
                  ChecklistItemSyncChip(syncStatus: widget.syncStatus!),
                ],
              ],
            ),
            if (widget.item.descriptionEs != null) ...[
              const SizedBox(height: 2),
              Text(
                widget.item.descriptionEs!,
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ChecklistStatusButton(
                  label: 'PASS',
                  value: 'pass',
                  current: status,
                  color: context.appColors.success,
                  onTap: () =>
                      widget.onStatusChanged(status == 'pass' ? null : 'pass'),
                ),
                const SizedBox(width: 8),
                ChecklistStatusButton(
                  label: 'MONITOR',
                  value: 'monitor',
                  current: status,
                  color: context.appColors.warning,
                  onTap: () => widget.onStatusChanged(
                    status == 'monitor' || status == 'alert' ? null : 'monitor',
                  ),
                ),
                const SizedBox(width: 8),
                ChecklistStatusButton(
                  label: 'ACTION',
                  value: 'action',
                  current: status,
                  color: context.appColors.error,
                  onTap: () => widget.onStatusChanged(
                    status == 'action' ? null : 'action',
                  ),
                ),
                const SizedBox(width: 8),
                ChecklistStatusButton(
                  label: 'N/A',
                  value: 'n/a',
                  current: status,
                  color: context.appColors.textSecondary,
                  onTap: () =>
                      widget.onStatusChanged(status == 'n/a' ? null : 'n/a'),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: showDetail
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        TextField(
                          controller: _noteCtrl,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Describe issue / action required',
                            hintStyle: TextStyle(
                              color: context.appColors.textSecondary,
                              fontSize: 12,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onChanged: widget.onNoteChanged,
                        ),
                        const SizedBox(height: 8),
                        if (hasPhotos)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (
                                  var i = 0;
                                  i < widget.uploadedPhotoUrls.length;
                                  i++
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _ChecklistPhotoTile(
                                      child: ChecklistPhotoPreview(
                                        photo: null,
                                        photoUrl: widget.uploadedPhotoUrls[i],
                                      ),
                                      onRemove: () =>
                                          widget.onUploadedPhotoRemoved(i),
                                    ),
                                  ),
                                for (
                                  var i = 0;
                                  i < widget.localPhotos.length;
                                  i++
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _ChecklistPhotoTile(
                                      child: ChecklistPhotoPreview(
                                        photo: widget.localPhotos[i],
                                        photoUrl: null,
                                      ),
                                      onRemove: () =>
                                          widget.onLocalPhotoRemoved(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (hasPhotos) const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.photo_library, size: 16),
                              label: const Text(
                                'Gallery',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt, size: 16),
                              label: const Text(
                                'Camera',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
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

class _ChecklistPhotoTile extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;

  const _ChecklistPhotoTile({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            icon: Icon(Icons.close, size: 16, color: context.appColors.error),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ),
      ],
    );
  }
}

class ChecklistPhotoPreview extends StatelessWidget {
  final Uint8List? photo;
  final String? photoUrl;

  const ChecklistPhotoPreview({
    super.key,
    required this.photo,
    required this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (photo != null) {
      return Image.memory(photo!, width: 60, height: 60, fit: BoxFit.cover);
    }

    final url = photoUrl;
    if (url == null || url.isEmpty) {
      return const ChecklistPhotoPlaceholder();
    }

    return ServiceReportImage(
      bucket: 'service-report-photos',
      reference: url,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
    );
  }
}

class ChecklistPhotoPlaceholder extends StatelessWidget {
  const ChecklistPhotoPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      color: context.appColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        Icons.photo,
        size: 20,
        color: context.appColors.textSecondary,
      ),
    );
  }
}

class ChecklistStatusButton extends StatelessWidget {
  final String label;
  final String value;
  final String? current;
  final Color color;
  final VoidCallback onTap;

  const ChecklistStatusButton({
    super.key,
    required this.label,
    required this.value,
    required this.current,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : context.appColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : context.appColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : context.appColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
