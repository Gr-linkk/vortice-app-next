import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/features/checklists/checklist_sync_banner.dart';
import 'package:vortice_app/models/checklist_item.dart';

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
    final file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file != null) {
      final bytes = await file.readAsBytes();
      widget.onPhotoAppended(bytes);
    }
  }

  Future<void> _takePhoto() async {
    final file =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (file != null) {
      final bytes = await file.readAsBytes();
      widget.onPhotoAppended(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final showDetail =
        status == 'alert' || status == 'monitor' || status == 'action';
    final hasPhotos = widget.localPhotos.isNotEmpty ||
        widget.uploadedPhotoUrls.isNotEmpty;

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
                  child: Text(widget.item.descriptionEn,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (syncStatusChipLabel(widget.syncStatus) != null) ...[
                  const SizedBox(width: 8),
                  ChecklistItemSyncChip(syncStatus: widget.syncStatus!),
                ],
              ],
            ),
            if (widget.item.descriptionEs != null) ...[
              const SizedBox(height: 2),
              Text(widget.item.descriptionEs!,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                ChecklistStatusButton(
                  label: 'PASS',
                  value: 'pass',
                  current: status,
                  color: AppColors.success,
                  onTap: () =>
                      widget.onStatusChanged(status == 'pass' ? null : 'pass'),
                ),
                const SizedBox(width: 8),
                ChecklistStatusButton(
                  label: 'MONITOR',
                  value: 'monitor',
                  current: status,
                  color: AppColors.warning,
                  onTap: () => widget.onStatusChanged(
                    status == 'monitor' || status == 'alert' ? null : 'monitor',
                  ),
                ),
                const SizedBox(width: 8),
                ChecklistStatusButton(
                  label: 'ACTION',
                  value: 'action',
                  current: status,
                  color: AppColors.error,
                  onTap: () => widget
                      .onStatusChanged(status == 'action' ? null : 'action'),
                ),
                const SizedBox(width: 8),
                ChecklistStatusButton(
                  label: 'N/A',
                  value: 'n/a',
                  current: status,
                  color: AppColors.textSecondary,
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
                          decoration: const InputDecoration(
                            hintText: 'Describe issue / action required',
                            hintStyle: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          onChanged: widget.onNoteChanged,
                        ),
                        const SizedBox(height: 8),
                        if (hasPhotos)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var i = 0;
                                    i < widget.uploadedPhotoUrls.length;
                                    i++)
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
                                for (var i = 0;
                                    i < widget.localPhotos.length;
                                    i++)
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
                              label: const Text('Gallery',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt, size: 16),
                              label: const Text('Camera',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
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

  const _ChecklistPhotoTile({
    required this.child,
    required this.onRemove,
  });

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
            icon: const Icon(Icons.close, size: 16, color: AppColors.error),
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
      return Image.memory(
        photo!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
      );
    }

    final url = photoUrl;
    if (url == null || url.isEmpty) {
      return const ChecklistPhotoPlaceholder();
    }

    return Image.network(
      url,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ChecklistPhotoPlaceholder(),
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
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: const Icon(
        Icons.photo,
        size: 20,
        color: AppColors.textSecondary,
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
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? color : AppColors.divider,
                width: selected ? 1.5 : 1),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
