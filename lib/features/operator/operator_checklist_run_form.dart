import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/operator/operator_checklist_quick_check_item.dart';
import 'package:vortice_app/features/operator/operator_checklist_run_header.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_template.dart';

class OperatorChecklistRunForm extends ConsumerStatefulWidget {
  final String assetName;
  final ChecklistTemplate template;
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final Map<String, Uint8List?> photos;
  final DateTime completedAt;
  final double? currentHours;
  final String? generalNotes;
  final String completedByLabel;
  final ValueChanged<DateTime> onCompletedAtChanged;
  final ValueChanged<double?> onCurrentHoursChanged;
  final ValueChanged<String?> onGeneralNotesChanged;
  final void Function(String id, String? v) onResponseChanged;
  final void Function(String id, String v) onNoteChanged;
  final void Function(String id, Uint8List? v) onPhotoChanged;
  final VoidCallback onSubmit;
  final VoidCallback onReset;
  final bool submitting;

  const OperatorChecklistRunForm({
    super.key,
    required this.assetName,
    required this.template,
    required this.responses,
    required this.notes,
    required this.photos,
    required this.completedAt,
    required this.currentHours,
    required this.generalNotes,
    required this.completedByLabel,
    required this.onCompletedAtChanged,
    required this.onCurrentHoursChanged,
    required this.onGeneralNotesChanged,
    required this.onResponseChanged,
    required this.onNoteChanged,
    required this.onPhotoChanged,
    required this.onSubmit,
    required this.onReset,
    required this.submitting,
  });

  @override
  ConsumerState<OperatorChecklistRunForm> createState() =>
      _OperatorChecklistRunFormState();
}

class _OperatorChecklistRunFormState
    extends ConsumerState<OperatorChecklistRunForm> {
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
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(checklistItemsProvider(widget.template.id));

    final headerWidgets = [
      OperatorChecklistRunHeader(
        assetLabel: widget.assetName,
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
            const Icon(
              Icons.directions_boat,
              color: AppColors.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${widget.assetName} — ${widget.template.name}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: widget.onReset,
              child: Text(l10n.change, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    ];

    return Column(
      children: [
        Expanded(
          child: itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                e.toString(),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
            data: (items) => ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                ...headerWidgets,
                for (final item in items)
                  OperatorChecklistQuickCheckItem(
                    item: item,
                    response: widget.responses[item.id],
                    note: widget.notes[item.id] ?? '',
                    photo: widget.photos[item.id],
                    onChanged: (v) => widget.onResponseChanged(item.id, v),
                    onNoteChanged: (v) => widget.onNoteChanged(item.id, v),
                    onPhotoChanged: (v) => widget.onPhotoChanged(item.id, v),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: widget.submitting ? null : widget.onSubmit,
            icon: widget.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(l10n.completeChecklist),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
          ),
        ),
      ],
    );
  }
}
