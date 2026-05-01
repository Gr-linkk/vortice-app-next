import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/models/checklist_template.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  final String workOrderId;
  final String? preSelectedTemplateId;
  const ChecklistScreen({
    super.key,
    required this.workOrderId,
    this.preSelectedTemplateId,
  });

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  ChecklistTemplate? _selectedTemplate;
  bool _showPicker = false;
  // response_status: 'pass', 'alert', 'action', or null (not answered)
  final Map<String, String?> _responses = {};
  final Map<String, String> _notes = {};
  final Map<String, Uint8List?> _photos = {};

  @override
  void initState() {
    super.initState();
    // If preSelectedTemplateId is provided, load that template immediately
    if (widget.preSelectedTemplateId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadPreSelectedTemplate();
      });
    }
  }

  Future<void> _loadPreSelectedTemplate() async {
    // Fetch the WO to get its assigned checklist template
    final woAsync = ref.watch(workOrderByIdProvider(widget.workOrderId));
    final wo = woAsync.valueOrNull;
    if (wo?.checklistTemplateId == null) return;

    final templates = ref.read(checklistTemplatesProvider).valueOrNull ?? [];
    final match = templates
        .where((t) => t.id == wo!.checklistTemplateId)
        .firstOrNull;
    if (match != null && mounted) {
      setState(() {
        _selectedTemplate = match;
        _showPicker = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final templatesAsync = ref.watch(checklistTemplatesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.checklistTitle),
        actions: [
          if (_selectedTemplate != null)
            TextButton.icon(
              onPressed: () => setState(() => _showPicker = !_showPicker),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(
                _showPicker ? 'Cancel' : l10n.change,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(err.toString(),
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (templates) {
          // Show picker if requested or no template selected
          if (_showPicker || _selectedTemplate == null) {
            return _GroupedTemplateSelector(
              templates: templates,
              preselected: _selectedTemplate,
              onSelect: (t) {
                setState(() {
                  _selectedTemplate = t;
                  _showPicker = false;
                });
              },
            );
          }

          return _ChecklistForm(
            template: _selectedTemplate!,
            workOrderId: widget.workOrderId,
            responses: _responses,
            notes: _notes,
            photos: _photos,
            onResponseChanged: (id, v) =>
                setState(() => _responses[id] = v),
            onNoteChanged: (id, v) =>
                setState(() => _notes[id] = v),
            onPhotoChanged: (id, v) =>
                setState(() => _photos[id] = v),
            onSubmit: () async {
              final ctrl = ref.read(checklistControllerProvider.notifier);
              await ctrl.submitBatch(
                workOrderId: widget.workOrderId,
                completedBy: profile?.id ?? '',
                responses: _responses,
                notes: _notes,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.checklistSubmitted),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
              if (context.mounted) context.pop();
            },
          );
        },
      ),
    );
  }
}

class _GroupedTemplateSelector extends StatelessWidget {
  final List<ChecklistTemplate> templates;
  final ChecklistTemplate? preselected;
  final ValueChanged<ChecklistTemplate> onSelect;

  const _GroupedTemplateSelector({
    required this.templates,
    this.preselected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Group templates by category
    final grouped = <String, List<ChecklistTemplate>>{};
    for (final t in templates) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }

    // Order: pre_ops first, then general, then dredge
    final orderedKeys = [
      'pre_ops',
      'general',
      'dredge',
      ...grouped.keys.where((k) => !['pre_ops', 'general', 'dredge'].contains(k)),
    ];

    final categoryLabel = {
      'pre_ops': 'Pre-Operations',
      'general': 'General',
      'dredge': 'Dredge',
    };

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final key in orderedKeys)
          if (grouped.containsKey(key)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                categoryLabel[key] ?? key.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
              ),
            ),
            ...grouped[key]!.map((t) => Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  color: preselected?.id == t.id
                      ? AppColors.primary.withOpacity(0.08)
                      : AppColors.surface,
                  child: ListTile(
                    leading: Icon(
                      Icons.checklist,
                      color: preselected?.id == t.id
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    title: Text(
                      t.name,
                      style: TextStyle(
                        fontWeight:
                            preselected?.id == t.id ? FontWeight.bold : null,
                      ),
                    ),
                    subtitle: t.description != null
                        ? Text(t.description!, maxLines: 1,
                                overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: preselected?.id == t.id
                        ? const Icon(Icons.check, color: AppColors.primary, size: 20)
                        : const Icon(Icons.chevron_right,
                                color: AppColors.textSecondary),
                    onTap: () => onSelect(t),
                  ),
                )),
          ],
      ],
    );
  }
}

class _ChecklistForm extends ConsumerStatefulWidget {
  final ChecklistTemplate template;
  final String workOrderId;
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final Map<String, Uint8List?> photos;
  final void Function(String id, String? v) onResponseChanged;
  final void Function(String id, String note) onNoteChanged;
  final void Function(String id, Uint8List? photo) onPhotoChanged;
  final VoidCallback onSubmit;

  const _ChecklistForm({
    required this.template,
    required this.workOrderId,
    required this.responses,
    required this.notes,
    required this.photos,
    required this.onResponseChanged,
    required this.onNoteChanged,
    required this.onPhotoChanged,
    required this.onSubmit,
  });

  @override
  ConsumerState<_ChecklistForm> createState() => _ChecklistFormState();
}

class _ChecklistFormState extends ConsumerState<_ChecklistForm> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(checklistItemsProvider(widget.template.id));
    final isLoading = ref.watch(checklistControllerProvider).isLoading;

    return Column(
      children: [
        // Template header
        Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.surfaceVariant,
          child: Row(
            children: [
              const Icon(Icons.checklist, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.template.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(err.toString(),
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (items) => ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (_, i) => _ChecklistItemWidget(
                item: items[i],
                status: widget.responses[items[i].id],
                note: widget.notes[items[i].id] ?? '',
                photo: widget.photos[items[i].id],
                onStatusChanged: (v) => widget.onResponseChanged(items[i].id, v),
                onNoteChanged: (v) => widget.onNoteChanged(items[i].id, v),
                onPhotoChanged: (v) => widget.onPhotoChanged(items[i].id, v),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : widget.onSubmit,
            icon: isLoading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: Colors.white))
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

class _ChecklistItemWidget extends StatefulWidget {
  final ChecklistItem item;
  final String? status; // 'pass', 'alert', 'action', or null
  final String note;
  final Uint8List? photo;
  final void Function(String? v) onStatusChanged;
  final void Function(String v) onNoteChanged;
  final void Function(Uint8List? v) onPhotoChanged;

  const _ChecklistItemWidget({
    required this.item,
    required this.status,
    required this.note,
    required this.photo,
    required this.onStatusChanged,
    required this.onNoteChanged,
    required this.onPhotoChanged,
  });

  @override
  State<_ChecklistItemWidget> createState() => _ChecklistItemWidgetState();
}

class _ChecklistItemWidgetState extends State<_ChecklistItemWidget> {
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _noteCtrl.text = widget.note;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70);
    if (file != null) {
      final bytes = await file.readAsBytes();
      widget.onPhotoChanged(bytes);
    }
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 70);
    if (file != null) {
      final bytes = await file.readAsBytes();
      widget.onPhotoChanged(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final showDetail = status == 'alert' || status == 'action';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item description
            Text(widget.item.descriptionEn,
                style: Theme.of(context).textTheme.titleSmall),
            if (widget.item.descriptionEs != null) ...[
              const SizedBox(height: 2),
              Text(widget.item.descriptionEs!,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 12),

            // 3-state buttons: PASS / ALERT / ACTION
            Row(
              children: [
                _StatusButton(
                  label: 'PASS',
                  value: 'pass',
                  current: status,
                  color: AppColors.success,
                  onTap: () => widget.onStatusChanged(
                      status == 'pass' ? null : 'pass'),
                ),
                const SizedBox(width: 8),
                _StatusButton(
                  label: 'ALERT',
                  value: 'alert',
                  current: status,
                  color: AppColors.warning,
                  onTap: () => widget.onStatusChanged(
                      status == 'alert' ? null : 'alert'),
                ),
                const SizedBox(width: 8),
                _StatusButton(
                  label: 'ACTION',
                  value: 'action',
                  current: status,
                  color: AppColors.error,
                  onTap: () => widget.onStatusChanged(
                      status == 'action' ? null : 'action'),
                ),
              ],
            ),

            // Comment + photo — always shown for alert/action, collapsible for pass
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: (showDetail || status == 'pass')
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        TextField(
                          controller: _noteCtrl,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: status == 'pass'
                                ? 'Add note (optional)'
                                : 'Describe issue / action required',
                            hintStyle: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          onChanged: widget.onNoteChanged,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (widget.photo != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(widget.photo!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    size: 16, color: AppColors.error),
                                onPressed: () =>
                                    widget.onPhotoChanged(null),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                            ],
                            OutlinedButton.icon(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.photo_library,
                                  size: 16),
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
                              icon: const Icon(Icons.camera_alt,
                                  size: 16),
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

class _StatusButton extends StatelessWidget {
  final String label;
  final String value;
  final String? current;
  final Color color;
  final VoidCallback onTap;

  const _StatusButton({
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
                ? color.withOpacity(0.18)
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
