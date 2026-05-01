import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

class OperatorChecklistScreen extends ConsumerStatefulWidget {
  final String? initialAssetId;
  const OperatorChecklistScreen({super.key, this.initialAssetId});

  @override
  ConsumerState<OperatorChecklistScreen> createState() =>
      _OperatorChecklistScreenState();
}

class _OperatorChecklistScreenState
    extends ConsumerState<OperatorChecklistScreen> {
  Map<String, dynamic>? _selectedAsset;
  ChecklistTemplate? _selectedTemplate;
  final String _runType = 'pre_departure';
  final Map<String, String?> _responses = {};
  final Map<String, String> _notes = {};
  final Map<String, Uint8List?> _photos = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAssetId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rows =
            ref.read(operatorAssignedAssetsProvider).valueOrNull ?? [];
        final row = rows
            .where((r) => r['id'] == widget.initialAssetId)
            .firstOrNull;
        if (row != null) setState(() => _selectedAsset = row);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(operatorAssignedAssetsProvider);
    final templatesAsync = ref.watch(checklistTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.operatorChecklistTitle)),
      body: _selectedAsset == null || _selectedTemplate == null
          ? _SelectionStep(
              assetsAsync: assetsAsync,
              templatesAsync: templatesAsync,
              selectedAsset: _selectedAsset,
              selectedTemplate: _selectedTemplate,
              onAssetSelected: (a) => setState(() => _selectedAsset = a),
              onTemplateSelected: (t) => setState(() => _selectedTemplate = t),
            )
          : _RunChecklist(
              assetName: _selectedAsset!['name'] as String,
              template: _selectedTemplate!,
              responses: _responses,
              notes: _notes,
              photos: _photos,
              onResponseChanged: (id, v) =>
                  setState(() => _responses[id] = v),
              onNoteChanged: (id, v) =>
                  setState(() => _notes[id] = v),
              onPhotoChanged: (id, v) =>
                  setState(() => _photos[id] = v),
              onSubmit: _submit,
              submitting: _submitting,
              onReset: () => setState(() {
                _selectedAsset = null;
                _selectedTemplate = null;
                _responses.clear();
                _notes.clear();
                _photos.clear();
              }),
            ),
    );
  }

  Future<void> _submit() async {
    final profile = ref.read(profileProvider).valueOrNull;
    setState(() => _submitting = true);
    try {
      final run = await supabase
          .from('operator_checklist_runs')
          .insert({
            'asset_id': _selectedAsset!['id'] as String,
            'operator_id': profile?.id,
            'template_id': _selectedTemplate!.id,
            'run_type': _runType,
            'completed_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final runId = run['id'] as String;

      if (_responses.isNotEmpty) {
        final rows = _responses.entries
            .where((e) => e.value != null)
            .map((e) => {
                  'run_id': runId,
                  'checklist_item_id': e.key,
                  'result': e.value,
                  'response_status': e.value,
                  if (_notes[e.key]?.isNotEmpty == true) 'notes': _notes[e.key],
                })
            .toList();
        await supabase.from('operator_checklist_responses').insert(rows);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).checklistSubmitted),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _selectedAsset = null;
          _selectedTemplate = null;
          _responses.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _SelectionStep extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> assetsAsync;
  final AsyncValue<List<ChecklistTemplate>> templatesAsync;
  final Map<String, dynamic>? selectedAsset;
  final ChecklistTemplate? selectedTemplate;
  final ValueChanged<Map<String, dynamic>> onAssetSelected;
  final ValueChanged<ChecklistTemplate> onTemplateSelected;

  const _SelectionStep({
    required this.assetsAsync,
    required this.templatesAsync,
    required this.selectedAsset,
    required this.selectedTemplate,
    required this.onAssetSelected,
    required this.onTemplateSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.selectAsset,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          assetsAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) =>
                Text(e.toString(), style: const TextStyle(color: AppColors.error)),
            data: (assets) {
              // Group by client
              final grouped = <String, List<Map<String, dynamic>>>{};
              for (final a in assets) {
                final client = (a['profiles'] as Map<String, dynamic>?)?['full_name']
                        as String? ??
                    'Unknown';
                grouped.putIfAbsent(client, () => []).add(a);
              }
              final clients = grouped.keys.toList()..sort();

              final allItems = <DropdownMenuItem<String>>[
                for (final client in clients)
                  for (final a in grouped[client]!)
                    DropdownMenuItem<String>(
                      value: a['id'] as String,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text('  ${a['name']}'),
                      ),
                    ),
              ];

              return DropdownButtonFormField<String>(
                value: selectedAsset?['id'] as String?,
                decoration: const InputDecoration(),
                dropdownColor: AppColors.surfaceVariant,
                items: allItems,
                hint: Text(l10n.selectAsset,
                    style: const TextStyle(color: AppColors.textSecondary)),
                onChanged: (id) {
                  if (id == null) return;
                  final asset = assets.firstWhere((a) => a['id'] == id);
                  onAssetSelected(asset);
                },
              );
            },
          ),
          const SizedBox(height: 24),
          Text(l10n.selectTemplate,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          templatesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) =>
                Text(e.toString(), style: const TextStyle(color: AppColors.error)),
            data: (templates) {
              final operatorTemplates = templates
                  .where((t) => t.checklistType == 'operator_daily')
                  .toList();
              return DropdownButtonFormField<String>(
                value: selectedTemplate?.id,
                decoration: const InputDecoration(),
                dropdownColor: AppColors.surfaceVariant,
                items: (operatorTemplates.isEmpty ? templates : operatorTemplates)
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name),
                        ))
                    .toList(),
                hint: Text(l10n.selectTemplate,
                    style: const TextStyle(color: AppColors.textSecondary)),
                onChanged: (id) {
                  if (id == null) return;
                  final tmpl = templates.firstWhere((t) => t.id == id);
                  onTemplateSelected(tmpl);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RunChecklist extends ConsumerWidget {
  final String assetName;
  final ChecklistTemplate template;
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final Map<String, Uint8List?> photos;
  final void Function(String id, String? v) onResponseChanged;
  final void Function(String id, String v) onNoteChanged;
  final void Function(String id, Uint8List? v) onPhotoChanged;
  final VoidCallback onSubmit;
  final VoidCallback onReset;
  final bool submitting;

  const _RunChecklist({
    required this.assetName,
    required this.template,
    required this.responses,
    required this.notes,
    required this.photos,
    required this.onResponseChanged,
    required this.onNoteChanged,
    required this.onPhotoChanged,
    required this.onSubmit,
    required this.onReset,
    required this.submitting,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(checklistItemsProvider(template.id));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.surfaceVariant,
          child: Row(
            children: [
              const Icon(Icons.directions_boat, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$assetName — ${template.name}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: onReset,
                child: Text(l10n.change, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(e.toString(),
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (items) => ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (_, i) => _QuickCheckItem(
                item: items[i],
                response: responses[items[i].id],
                note: notes[items[i].id] ?? '',
                photo: photos[items[i].id],
                onChanged: (v) => onResponseChanged(items[i].id, v),
                onNoteChanged: (v) => onNoteChanged(items[i].id, v),
                onPhotoChanged: (v) => onPhotoChanged(items[i].id, v),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
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

class _QuickCheckItem extends StatefulWidget {
  final ChecklistItem item;
  final String? response;
  final String note;
  final Uint8List? photo;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<Uint8List?> onPhotoChanged;

  const _QuickCheckItem({
    required this.item,
    required this.response,
    required this.note,
    required this.photo,
    required this.onChanged,
    required this.onNoteChanged,
    required this.onPhotoChanged,
  });

  @override
  State<_QuickCheckItem> createState() => _QuickCheckItemState();
}

class _QuickCheckItemState extends State<_QuickCheckItem> {
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
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file != null) widget.onPhotoChanged(await file.readAsBytes());
  }

  Future<void> _takePhoto() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (file != null) widget.onPhotoChanged(await file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.response;
    final showDetail = status == 'alert' || status == 'action';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.descriptionEn,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatusButton(label: 'PASS', value: 'pass', current: status,
                    color: AppColors.success,
                    onTap: () => widget.onChanged(status == 'pass' ? null : 'pass')),
                const SizedBox(width: 6),
                _StatusButton(label: 'ALERT', value: 'alert', current: status,
                    color: AppColors.warning,
                    onTap: () => widget.onChanged(status == 'alert' ? null : 'alert')),
                const SizedBox(width: 6),
                _StatusButton(label: 'ACTION', value: 'action', current: status,
                    color: AppColors.error,
                    onTap: () => widget.onChanged(status == 'action' ? null : 'action')),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: (showDetail || status == 'pass')
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteCtrl,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: status == 'pass' ? 'Note (optional)' : 'Describe issue / action',
                            hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          ),
                          onChanged: widget.onNoteChanged,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (widget.photo != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.memory(widget.photo!, width: 48, height: 48, fit: BoxFit.cover),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 14, color: AppColors.error),
                                onPressed: () => widget.onPhotoChanged(null),
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 4),
                            ],
                            OutlinedButton.icon(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.photo_library, size: 14),
                              label: const Text('Photo', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                            const SizedBox(width: 4),
                            OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt, size: 14),
                              label: const Text('Camera', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    required this.label, required this.value, required this.current,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.18) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: selected ? color : AppColors.divider, width: selected ? 1.5 : 1),
          ),
          alignment: Alignment.center,
          child: Text(label,
            style: TextStyle(
              color: selected ? color : AppColors.textSecondary,
              fontWeight: FontWeight.bold, fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
