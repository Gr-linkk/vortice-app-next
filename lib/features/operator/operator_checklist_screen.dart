import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/saved_checklists_repository.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

class OperatorChecklistScreen extends ConsumerStatefulWidget {
  final String? initialAssetId;
  final String? initialTemplateId;
  const OperatorChecklistScreen({
    super.key,
    this.initialAssetId,
    this.initialTemplateId,
  });

  @override
  ConsumerState<OperatorChecklistScreen> createState() =>
      _OperatorChecklistScreenState();
}

class _OperatorChecklistScreenState
    extends ConsumerState<OperatorChecklistScreen> {
  static const _offlineSubmitMessage =
      'Checklist could not be submitted right now. Reconnect and try again.';
  static const _photoNotSubmittedMessage =
      'Checklist saved, but attached photos stay on this device for now and were not submitted.';
  static const _draftKey = 'operator_checklist_draft';
  Map<String, dynamic>? _selectedAsset;
  ChecklistTemplate? _selectedTemplate;
  final String _runType = 'pre_departure';
  final Map<String, String?> _responses = {};
  final Map<String, String> _notes = {};
  final Map<String, Uint8List?> _photos = {};
  bool _submitting = false;
  bool _restoredDraft = false;
  DateTime _completedAt = DateTime.now();
  double? _currentHours;
  String? _generalNotes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraftIfReady());
  }

  Future<void> _restoreDraftIfReady() async {
    if (_restoredDraft) return;

    final assets = ref.read(operatorAssignedAssetsProvider).valueOrNull;
    final templates = ref.read(checklistTemplatesProvider).valueOrNull;
    if (assets == null || templates == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);

    Map<String, dynamic>? assetToSet = _selectedAsset;
    ChecklistTemplate? templateToSet = _selectedTemplate;

    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final assetId = data['assetId'] as String?;
        final templateId = data['templateId'] as String?;
        final responses =
            (data['responses'] as Map?)?.cast<String, dynamic>() ?? {};
        final notes = (data['notes'] as Map?)?.cast<String, dynamic>() ?? {};
        final photos = (data['photos'] as Map?)?.cast<String, dynamic>() ?? {};
        final completedAtRaw = data['completedAt'] as String?;
        if (completedAtRaw != null) {
          _completedAt = DateTime.tryParse(completedAtRaw) ?? _completedAt;
        }
        _currentHours = (data['currentHours'] as num?)?.toDouble();
        _generalNotes = data['generalNotes'] as String?;

        assetToSet = assetId == null
            ? null
            : assets.where((r) => r['id'] == assetId).firstOrNull;
        templateToSet = templateId == null
            ? null
            : templates.where((t) => t.id == templateId).firstOrNull;

        if (mounted) {
          setState(() {
            _selectedAsset = assetToSet;
            _selectedTemplate = templateToSet;
            _responses
              ..clear()
              ..addAll(
                responses.map(
                  (key, value) => MapEntry(key, value as String?),
                ),
              );
            _notes
              ..clear()
              ..addAll(
                notes.map(
                  (key, value) => MapEntry(key, value as String),
                ),
              );
            _photos
              ..clear()
              ..addAll(
                photos.map(
                  (key, value) => MapEntry(
                    key,
                    value is String && value.isNotEmpty
                        ? base64Decode(value)
                        : null,
                  ),
                ),
              );
          });
        }
      } catch (_) {
        await prefs.remove(_draftKey);
      }
    }

    if (assetToSet == null && widget.initialAssetId != null) {
      assetToSet =
          assets.where((r) => r['id'] == widget.initialAssetId).firstOrNull;
    }
    if (templateToSet == null && widget.initialTemplateId != null) {
      templateToSet =
          templates.where((t) => t.id == widget.initialTemplateId).firstOrNull;
    }
    if (mounted) {
      setState(() {
        _selectedAsset = assetToSet;
        _selectedTemplate = templateToSet;
      });
    }

    _restoredDraft = true;
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _draftKey,
      jsonEncode({
        'assetId': _selectedAsset?['id'] as String?,
        'templateId': _selectedTemplate?.id,
        'responses': _responses,
        'notes': _notes,
        'completedAt': _completedAt.toIso8601String(),
        'currentHours': _currentHours,
        'generalNotes': _generalNotes,
        'photos': _photos.map(
          (key, value) => MapEntry(
            key,
            value == null ? null : base64Encode(value),
          ),
        ),
      }),
    );
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  void _resetChecklist() {
    setState(() {
      _selectedAsset = null;
      _selectedTemplate = null;
      _responses.clear();
      _notes.clear();
      _photos.clear();
      _completedAt = DateTime.now();
      _currentHours = null;
      _generalNotes = null;
    });
    _saveDraft();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final assetsAsync = ref.watch(operatorAssignedAssetsProvider);
    final templatesAsync = ref.watch(checklistTemplatesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    ref.listen(operatorAssignedAssetsProvider, (_, next) {
      if (next.hasValue) {
        unawaited(_restoreDraftIfReady());
      }
    });
    ref.listen(checklistTemplatesProvider, (_, next) {
      if (next.hasValue) {
        unawaited(_restoreDraftIfReady());
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.operatorChecklistTitle)),
      body: _selectedAsset == null || _selectedTemplate == null
          ? _SelectionStep(
              assetsAsync: assetsAsync,
              templatesAsync: templatesAsync,
              selectedAsset: _selectedAsset,
              selectedTemplate: _selectedTemplate,
              onAssetSelected: (a) {
                setState(() => _selectedAsset = a);
                _saveDraft();
              },
              onTemplateSelected: (t) {
                setState(() => _selectedTemplate = t);
                _saveDraft();
              },
            )
          : _RunChecklist(
              assetName: _selectedAsset!['name'] as String,
              template: _selectedTemplate!,
              responses: _responses,
              notes: _notes,
              photos: _photos,
              completedAt: _completedAt,
              currentHours: _currentHours,
              generalNotes: _generalNotes,
              completedByLabel:
                  profile?.fullName ?? profile?.email ?? profile?.id ?? '—',
              onCompletedAtChanged: (value) {
                setState(() => _completedAt = value);
                _saveDraft();
              },
              onCurrentHoursChanged: (value) {
                setState(() => _currentHours = value);
                _saveDraft();
              },
              onGeneralNotesChanged: (value) {
                setState(() => _generalNotes = value);
                _saveDraft();
              },
              onResponseChanged: (id, v) {
                setState(() => _responses[id] = v);
                _saveDraft();
              },
              onNoteChanged: (id, v) {
                setState(() => _notes[id] = v);
                _saveDraft();
              },
              onPhotoChanged: (id, v) {
                setState(() => _photos[id] = v);
                _saveDraft();
              },
              onSubmit: _submit,
              submitting: _submitting,
              onReset: _resetChecklist,
            ),
    );
  }

  Future<void> _submit() async {
    final profile = ref.read(profileProvider).valueOrNull;
    await _saveDraft();
    setState(() => _submitting = true);
    try {
      if (_requiresAttentionDetail(_responses, _notes, _photos)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Monitor and Action items need a note or photo.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
      final run = await supabase
          .from('operator_checklist_runs')
          .insert({
            'asset_id': _selectedAsset!['id'] as String,
            'operator_id': profile?.id,
            'template_id': _selectedTemplate!.id,
            'run_type': _runType,
            'completed_at': _completedAt.toIso8601String(),
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 4));

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
        await supabase
            .from('operator_checklist_responses')
            .insert(rows)
            .timeout(const Duration(seconds: 4));
      }

      final items =
          await ref.read(checklistItemsProvider(_selectedTemplate!.id).future);
      await ref.read(savedChecklistsRepositoryProvider).createSavedChecklist(
            assetId: _selectedAsset!['id'] as String,
            clientId: _selectedAsset!['client_id'] as String? ??
                (run['client_id'] as String? ?? ''),
            template: _selectedTemplate!,
            items: items,
            responses: _responses,
            notes: _notes,
            photoUrls: const {},
            sourceType: 'operator',
            checklistType: 'operations',
            completedBy: profile?.id ?? '',
            submittedByRole: profile?.role.name,
            submittedAt: _completedAt,
            currentHours: _currentHours,
            generalNotes: _generalNotes,
            extraHeader: {
              'run_id': runId,
              'run_type': _runType,
            },
          );

      final hasPhotos = _photos.values.any((photo) => photo != null);
      await _clearDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasPhotos
                  ? _photoNotSubmittedMessage
                  : AppLocalizations.of(context).checklistSubmitted,
            ),
            backgroundColor: hasPhotos ? AppColors.warning : AppColors.success,
          ),
        );
        setState(() {
          _selectedAsset = null;
          _selectedTemplate = null;
          _responses.clear();
          _notes.clear();
          _photos.clear();
          _completedAt = DateTime.now();
          _currentHours = null;
          _generalNotes = null;
        });
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(_offlineSubmitMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(_offlineSubmitMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

bool _requiresAttentionDetail(
  Map<String, String?> responses,
  Map<String, String> notes,
  Map<String, Uint8List?> photos,
) {
  for (final entry in responses.entries) {
    final status = entry.value;
    if (status != 'monitor' && status != 'alert' && status != 'action') {
      continue;
    }
    final hasNote = notes[entry.key]?.trim().isNotEmpty == true;
    final hasPhoto = photos[entry.key] != null;
    if (!hasNote && !hasPhoto) return true;
  }
  return false;
}

String _formatOperatorDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class _OperatorRunHeader extends StatelessWidget {
  final String assetLabel;
  final String checklistLabel;
  final String completedByLabel;
  final DateTime completedAt;
  final TextEditingController hoursController;
  final TextEditingController notesController;
  final VoidCallback onPickCompletedAt;
  final ValueChanged<double?> onHoursChanged;
  final ValueChanged<String?> onNotesChanged;

  const _OperatorRunHeader({
    required this.assetLabel,
    required this.checklistLabel,
    required this.completedByLabel,
    required this.completedAt,
    required this.hoursController,
    required this.notesController,
    required this.onPickCompletedAt,
    required this.onHoursChanged,
    required this.onNotesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Run details', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text('Asset: $assetLabel',
              style: Theme.of(context).textTheme.bodySmall),
          Text('Checklist: $checklistLabel',
              style: Theme.of(context).textTheme.bodySmall),
          Text('Completed by: $completedByLabel',
              style: Theme.of(context).textTheme.bodySmall),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Date/time'),
            subtitle: Text(_formatOperatorDateTime(completedAt)),
            trailing: const Icon(Icons.edit_calendar, size: 18),
            onTap: onPickCompletedAt,
          ),
          TextField(
            controller: hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Current hours (optional)',
              isDense: true,
            ),
            onChanged: (value) => onHoursChanged(double.tryParse(value.trim())),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'General notes (optional)',
              isDense: true,
            ),
            onChanged: (value) => onNotesChanged(
              value.trim().isEmpty ? null : value.trim(),
            ),
          ),
        ],
      ),
    );
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
            error: (e, _) => Text(e.toString(),
                style: const TextStyle(color: AppColors.error)),
            data: (assets) {
              // Group by client
              final grouped = <String, List<Map<String, dynamic>>>{};
              for (final a in assets) {
                final client = (a['profiles']
                        as Map<String, dynamic>?)?['full_name'] as String? ??
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
                initialValue: selectedAsset?['id'] as String?,
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
            error: (e, _) => Text(e.toString(),
                style: const TextStyle(color: AppColors.error)),
            data: (templates) {
              final operatorTemplates = templates
                  .where((t) => t.checklistType == 'operator_daily')
                  .toList();
              return DropdownButtonFormField<String>(
                initialValue: selectedTemplate?.id,
                decoration: const InputDecoration(),
                dropdownColor: AppColors.surfaceVariant,
                items:
                    (operatorTemplates.isEmpty ? templates : operatorTemplates)
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

class _RunChecklist extends ConsumerStatefulWidget {
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

  const _RunChecklist({
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
  ConsumerState<_RunChecklist> createState() => _RunChecklistState();
}

class _RunChecklistState extends ConsumerState<_RunChecklist> {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(checklistItemsProvider(widget.template.id));

    final headerWidgets = [
      _OperatorRunHeader(
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
            const Icon(Icons.directions_boat,
                color: AppColors.primary, size: 18),
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
              child: Text(e.toString(),
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (items) => ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                ...headerWidgets,
                for (final item in items)
                  _QuickCheckItem(
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
  void didUpdateWidget(covariant _QuickCheckItem oldWidget) {
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
            Text(widget.item.descriptionEn,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatusButton(
                    label: 'PASS',
                    value: 'pass',
                    current: status,
                    color: AppColors.success,
                    onTap: () =>
                        widget.onChanged(status == 'pass' ? null : 'pass')),
                const SizedBox(width: 6),
                _StatusButton(
                    label: 'MONITOR',
                    value: 'monitor',
                    current: status,
                    color: AppColors.warning,
                    onTap: () => widget.onChanged(
                        status == 'monitor' || status == 'alert'
                            ? null
                            : 'monitor')),
                const SizedBox(width: 6),
                _StatusButton(
                    label: 'ACTION',
                    value: 'action',
                    current: status,
                    color: AppColors.error,
                    onTap: () =>
                        widget.onChanged(status == 'action' ? null : 'action')),
                const SizedBox(width: 6),
                _StatusButton(
                    label: 'N/A',
                    value: 'n/a',
                    current: status,
                    color: AppColors.textSecondary,
                    onTap: () =>
                        widget.onChanged(status == 'n/a' ? null : 'n/a')),
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
                                color: AppColors.textSecondary, fontSize: 12),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                          ),
                          onChanged: widget.onNoteChanged,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (widget.photo != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.memory(widget.photo!,
                                    width: 48, height: 48, fit: BoxFit.cover),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    size: 14, color: AppColors.error),
                                onPressed: () => widget.onPhotoChanged(null),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 4),
                            ],
                            OutlinedButton.icon(
                              onPressed: _pickPhoto,
                              icon: const Icon(Icons.photo_library, size: 14),
                              label: const Text('Photo',
                                  style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                              ),
                            ),
                            const SizedBox(width: 4),
                            OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt, size: 14),
                              label: const Text('Camera',
                                  style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
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
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(7),
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
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
