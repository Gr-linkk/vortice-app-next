import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_attachment_support.dart';
import 'package:vortice_app/features/checklists/checklist_item_widget.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/checklist_run_header.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/features/checklists/checklist_sync_banner.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_response.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

class ChecklistForm extends ConsumerStatefulWidget {
  final ChecklistTemplate template;
  final String workOrderId;
  final bool showSyncStatus;
  final List<ChecklistItem>? snapshotItems;
  final String? metadataCaption;
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final ChecklistItemPhotoLists photos;
  final Map<String, String?> photoUrls;
  final DateTime completedAt;
  final double? currentHours;
  final String? generalNotes;
  final String assetLabel;
  final String completedByLabel;
  final ValueChanged<DateTime> onCompletedAtChanged;
  final ValueChanged<double?> onCurrentHoursChanged;
  final ValueChanged<String?> onGeneralNotesChanged;
  final void Function(String id, String? v) onResponseChanged;
  final void Function(String id, String note) onNoteChanged;
  final void Function(String id, Uint8List bytes) onPhotoAppended;
  final void Function(String id, int index) onLocalPhotoRemoved;
  final void Function(String id, int index) onUploadedPhotoRemoved;
  final VoidCallback onSubmit;

  const ChecklistForm({
    super.key,
    required this.template,
    required this.workOrderId,
    required this.showSyncStatus,
    this.snapshotItems,
    this.metadataCaption,
    required this.responses,
    required this.notes,
    required this.photos,
    required this.photoUrls,
    required this.completedAt,
    required this.currentHours,
    required this.generalNotes,
    required this.assetLabel,
    required this.completedByLabel,
    required this.onCompletedAtChanged,
    required this.onCurrentHoursChanged,
    required this.onGeneralNotesChanged,
    required this.onResponseChanged,
    required this.onNoteChanged,
    required this.onPhotoAppended,
    required this.onLocalPhotoRemoved,
    required this.onUploadedPhotoRemoved,
    required this.onSubmit,
  });

  @override
  ConsumerState<ChecklistForm> createState() => _ChecklistFormState();
}

class _ChecklistFormState extends ConsumerState<ChecklistForm> {
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _hoursCtrl =
        TextEditingController(text: widget.currentHours?.toString() ?? '');
    _notesCtrl = TextEditingController(text: widget.generalNotes ?? '');
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCompletedAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: widget.completedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(widget.completedAt),
    );
    if (time == null) return;
    widget.onCompletedAtChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _retrySync() async {
    await ref
        .read(checklistControllerProvider.notifier)
        .retryPendingResponses(widget.workOrderId);
    final state = ref.read(checklistControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      final error = state.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checklist sync still pending: $error'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checklist sync retried.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = widget.snapshotItems != null
        ? AsyncValue.data(widget.snapshotItems!)
        : ref.watch(checklistItemsProvider(widget.template.id));
    final isLoading = ref.watch(checklistControllerProvider).isLoading;
    final List<ChecklistResponse> checklistResponses = widget.showSyncStatus
        ? ref
                .watch(checklistResponsesProvider(widget.workOrderId))
                .valueOrNull ??
            const <ChecklistResponse>[]
        : const <ChecklistResponse>[];
    final syncStatusByItem = {
      for (final response in checklistResponses)
        response.checklistItemId: response.syncStatus,
    };
    final visibleSyncStatuses = syncStatusByItem.values
        .where(isVisibleChecklistSyncStatus)
        .toList(growable: false);
    final hasSyncConflict = visibleSyncStatuses.contains(
      SyncStatusValues.conflict,
    );
    final syncLastError = checklistResponses
        .where((response) => response.lastError?.trim().isNotEmpty == true)
        .map((response) => response.lastError!)
        .firstOrNull;

    final headerWidgets = [
      ChecklistRunHeader(
        assetLabel: widget.assetLabel,
        checklistLabel: widget.template.name,
        completedByLabel: widget.completedByLabel,
        completedAt: widget.completedAt,
        hoursController: _hoursCtrl,
        notesController: _notesCtrl,
        onPickCompletedAt: _pickCompletedAt,
        onHoursChanged: widget.onCurrentHoursChanged,
        onNotesChanged: widget.onGeneralNotesChanged,
      ),
      Container(
        padding: const EdgeInsets.all(12),
        color: AppColors.surfaceVariant,
        child: Row(
          children: [
            const Icon(Icons.checklist, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.template.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (widget.metadataCaption?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        widget.metadataCaption!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (visibleSyncStatuses.isNotEmpty)
        ChecklistSyncStatusBanner(
          hasConflict: hasSyncConflict,
          message: checklistSyncBannerMessage(
            hasConflict: hasSyncConflict,
            lastError: syncLastError,
          ),
          onRetry: _retrySync,
          isRetrying: isLoading,
        ),
    ];

    return Column(
      children: [
        Expanded(
          child: itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(err.toString(),
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (items) => ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                ...headerWidgets,
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (final item in items)
                        ChecklistItemWidget(
                          item: item,
                          status: widget.responses[item.id],
                          note: widget.notes[item.id] ?? '',
                          localPhotos: checklistPhotosForItem(
                            widget.photos,
                            item.id,
                          ),
                          uploadedPhotoUrls: parseChecklistPhotoUrls(
                            widget.photoUrls[item.id],
                          ),
                          syncStatus: syncStatusByItem[item.id],
                          onStatusChanged: (v) =>
                              widget.onResponseChanged(item.id, v),
                          onNoteChanged: (v) =>
                              widget.onNoteChanged(item.id, v),
                          onPhotoAppended: (bytes) =>
                              widget.onPhotoAppended(item.id, bytes),
                          onLocalPhotoRemoved: (index) =>
                              widget.onLocalPhotoRemoved(item.id, index),
                          onUploadedPhotoRemoved: (index) =>
                              widget.onUploadedPhotoRemoved(item.id, index),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : widget.onSubmit,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(l10n.submitChecklist),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }
}
