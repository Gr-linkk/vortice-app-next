import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/checklist_repository.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  final String? workOrderId;
  final String? assetId;
  final String? assetClientId;
  final String? assetName;
  final String? assetTypeId;
  final bool clientHistoryOnly;
  final String? preSelectedTemplateId;

  const ChecklistScreen({
    super.key,
    this.workOrderId,
    this.assetId,
    this.assetClientId,
    this.assetName,
    this.assetTypeId,
    this.clientHistoryOnly = false,
    this.preSelectedTemplateId,
  }) : assert(
          workOrderId != null || (assetId != null && assetClientId != null),
          'ChecklistScreen needs a work order or asset/client pair.',
        );

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  ChecklistTemplate? _selectedTemplate;
  String? _draftTemplateId;
  bool _showPicker = false;
  // response_status: 'pass', 'monitor', 'action', 'n/a', or null (not answered)
  final Map<String, String?> _responses = {};
  final Map<String, String> _notes = {};
  final Map<String, Uint8List?> _photos = {};
  final Map<String, String?> _photoUrls = {};
  String? _photoUploadDeferredReason;
  DateTime _completedAt = DateTime.now();
  double? _currentHours;
  String? _generalNotes;

  @override
  void initState() {
    super.initState();
    // If preSelectedTemplateId is provided, load that template immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSavedChecklistState();
      if (widget.preSelectedTemplateId != null) {
        await _loadPreSelectedTemplate();
      }
    });
  }

  String get _checklistRunKey =>
      widget.workOrderId ?? 'asset_${widget.assetId}';
  String get _draftKey => 'checklist_draft_$_checklistRunKey';
  String get _photoCacheKey => 'checklist_photo_cache_$_checklistRunKey';

  Future<void> _loadCachedPhotos(SharedPreferences prefs) async {
    final raw = prefs.getString(_photoCacheKey);
    if (raw == null) return;
    try {
      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is String && value.isNotEmpty) {
          _photos[entry.key] = base64Decode(value);
        }
      }
    } catch (_) {
      await prefs.remove(_photoCacheKey);
    }
  }

  Future<void> _savePhotoCache() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, String>{};
    for (final entry in _photos.entries) {
      final bytes = entry.value;
      if (bytes != null) {
        encoded[entry.key] = base64Encode(bytes);
      }
    }

    if (encoded.isEmpty) {
      await prefs.remove(_photoCacheKey);
      return;
    }

    await prefs.setString(_photoCacheKey, jsonEncode(encoded));
  }

  Future<void> _loadSavedChecklistState() async {
    try {
      final workOrderId = widget.workOrderId;
      if (workOrderId != null) {
        final savedResponses = await ref
            .read(checklistRepositoryProvider)
            .listResponsesForWorkOrder(workOrderId);
        for (final response in savedResponses) {
          final itemId = response.checklistItemId;
          _responses[itemId] = response.responseStatus ??
              (response.completed ? 'pass' : 'monitor');
          final note = response.notes;
          if (note?.isNotEmpty == true) {
            _notes[itemId] = note!;
          }
          final photoUrl = response.photoUrl;
          final hasLocalPendingPhoto =
              response.syncStatus != SyncStatusValues.synced &&
                  response.lastError != null &&
                  response.lastError!.isNotEmpty;
          if (photoUrl?.isNotEmpty == true && !hasLocalPendingPhoto) {
            _photoUrls[itemId] = photoUrl;
          }
        }
      }
    } catch (_) {
      // Local draft restore below is the important no-data-loss path.
    }

    final prefs = await SharedPreferences.getInstance();
    await _loadCachedPhotos(prefs);
    final raw = prefs.getString(_draftKey);
    var restoredDraftPhotos = false;
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final responses =
            (data['responses'] as Map?)?.cast<String, dynamic>() ?? {};
        final notes = (data['notes'] as Map?)?.cast<String, dynamic>() ?? {};
        final photos = (data['photos'] as Map?)?.cast<String, dynamic>() ?? {};
        final photoUrls =
            (data['photoUrls'] as Map?)?.cast<String, dynamic>() ?? {};
        _draftTemplateId = data['templateId'] as String?;
        final completedAtRaw = data['completedAt'] as String?;
        if (completedAtRaw != null) {
          _completedAt = DateTime.tryParse(completedAtRaw) ?? _completedAt;
        }
        _currentHours = (data['currentHours'] as num?)?.toDouble();
        _generalNotes = data['generalNotes'] as String?;
        for (final e in responses.entries) {
          _responses[e.key] = e.value as String?;
        }
        for (final e in notes.entries) {
          _notes[e.key] = e.value as String;
        }
        for (final e in photoUrls.entries) {
          final hasLocalPhoto =
              photos[e.key] is String && (photos[e.key] as String).isNotEmpty;
          if (!hasLocalPhoto) {
            _photoUrls[e.key] = e.value as String?;
          }
        }
        for (final e in photos.entries) {
          if (e.value is String && (e.value as String).isNotEmpty) {
            _photos[e.key] = base64Decode(e.value as String);
            restoredDraftPhotos = true;
          }
        }
      } catch (_) {
        await prefs.remove(_draftKey);
      }
    }
    if (restoredDraftPhotos) {
      await _savePhotoCache();
      await _saveDraft();
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _draftKey,
      jsonEncode({
        'templateId': _selectedTemplate?.id ?? _draftTemplateId,
        'responses': _responses,
        'notes': _notes,
        'photoUrls': _photoUrls,
        'completedAt': _completedAt.toIso8601String(),
        'currentHours': _currentHours,
        'generalNotes': _generalNotes,
        'photos': _photos.map(
          (key, value) =>
              MapEntry(key, value == null ? null : base64Encode(value)),
        ),
      }),
    );
  }

  Future<Map<String, String?>> _uploadChecklistPhotos() async {
    _photoUploadDeferredReason = null;
    final urls = Map<String, String?>.from(_photoUrls);
    for (final entry in _photos.entries) {
      final bytes = entry.value;
      if (bytes == null) {
        urls[entry.key] = null;
        continue;
      }
      final existingUrl = urls[entry.key];
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'checklists/$_checklistRunKey/${entry.key}_$ts.jpg';
      try {
        await supabase.storage
            .from(AppConstants.bucketReportPhotos)
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            )
            .timeout(const Duration(seconds: 4));
        urls[entry.key] = supabase.storage
            .from(AppConstants.bucketReportPhotos)
            .getPublicUrl(path);
      } on TimeoutException catch (error) {
        _photoUploadDeferredReason ??= error.toString();
        urls[entry.key] = existingUrl;
      } catch (error) {
        _photoUploadDeferredReason ??= error.toString();
        urls[entry.key] = existingUrl;
      }
    }
    return urls;
  }

  Future<void> _loadPreSelectedTemplate() async {
    final templateId = widget.preSelectedTemplateId;
    if (templateId == null) return;

    final templates = ref.read(checklistTemplatesProvider).valueOrNull ?? [];
    final match = templates.where((t) => t.id == templateId).firstOrNull;
    if (match != null && mounted) {
      setState(() {
        _selectedTemplate = match;
        _draftTemplateId = match.id;
        _showPicker = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final templatesAsync = ref.watch(checklistTemplatesProvider);
    final workOrderId = widget.workOrderId;
    final workOrder = workOrderId == null
        ? null
        : ref.watch(workOrderByIdProvider(workOrderId)).valueOrNull;
    final snapshot = workOrderId == null
        ? null
        : ref
            .watch(workOrderChecklistSnapshotProvider(workOrderId))
            .valueOrNull;
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetName = widget.assetName ??
        (workOrder == null
            ? null
            : ref.watch(assetNameProvider(workOrder.assetId)).valueOrNull);
    final boundTemplateId = snapshot?.templateId ??
        workOrder?.checklistTemplateId ??
        widget.preSelectedTemplateId;
    final templateSelectionLocked = boundTemplateId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.checklistTitle),
        actions: [
          if (!templateSelectionLocked && _selectedTemplate != null)
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
        data: (allTemplates) {
          final templates = widget.clientHistoryOnly
              ? templatesForAssetChecklist(
                  templates: allTemplates,
                  assetTypeId: widget.assetTypeId,
                )
              : allTemplates;
          final snapshotTemplate = snapshot?.asTemplate();

          if (snapshotTemplate != null &&
              (boundTemplateId == null ||
                  snapshot?.templateId == boundTemplateId)) {
            _selectedTemplate = snapshotTemplate;
            _draftTemplateId = snapshot?.templateId ?? _draftTemplateId;
            _showPicker = false;
          } else if (_selectedTemplate == null && boundTemplateId != null) {
            final matches = templates.where((t) => t.id == boundTemplateId);
            if (matches.isNotEmpty) {
              _selectedTemplate = matches.first;
              _draftTemplateId = matches.first.id;
              _showPicker = false;
            }
          } else if (_selectedTemplate == null && _draftTemplateId != null) {
            final matches = templates.where((t) => t.id == _draftTemplateId);
            if (matches.isNotEmpty) {
              _selectedTemplate = matches.first;
              _showPicker = false;
            }
          }

          if (!templateSelectionLocked &&
              (_showPicker || _selectedTemplate == null)) {
            return _GroupedTemplateSelector(
              templates: templates,
              emptyMessage: widget.clientHistoryOnly
                  ? 'No checklists are assigned to this asset type yet.'
                  : 'No checklist templates available.',
              preselected: _selectedTemplate,
              onSelect: (t) {
                setState(() {
                  _selectedTemplate = t;
                  _draftTemplateId = t.id;
                  _showPicker = false;
                });
                _saveDraft();
              },
            );
          }

          if (_selectedTemplate == null) {
            return const Center(
              child: Text(
                'Checklist template unavailable for this work order.',
                style: TextStyle(color: AppColors.error),
              ),
            );
          }

          final snapshotItems = snapshot != null &&
                  snapshot.items.isNotEmpty &&
                  (snapshot.templateId == _selectedTemplate!.id ||
                      snapshotTemplate?.id == _selectedTemplate!.id)
              ? snapshot.items
              : null;
          final metaBits = <String>[];
          if (snapshot?.intervalLabel?.trim().isNotEmpty == true) {
            metaBits.add(snapshot!.intervalLabel!.trim());
          }
          if ((snapshot?.intervalHours ?? 0) > 0) {
            metaBits.add('${snapshot!.intervalHours}h');
          }
          if ((snapshot?.templateVersion ?? 0) > 0) {
            metaBits.add('v${snapshot!.templateVersion}');
          }
          if (snapshotItems != null) {
            metaBits.add('${snapshotItems.length} items');
          }

          return _ChecklistForm(
            template: _selectedTemplate!,
            workOrderId: _checklistRunKey,
            showSyncStatus: widget.workOrderId != null,
            snapshotItems: snapshotItems,
            metadataCaption: metaBits.isEmpty ? null : metaBits.join(' • '),
            responses: _responses,
            notes: _notes,
            photos: _photos,
            photoUrls: _photoUrls,
            completedAt: _completedAt,
            currentHours: _currentHours,
            generalNotes: _generalNotes,
            assetLabel: assetName ?? workOrder?.assetId ?? '—',
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
              setState(() {
                if (v == null) {
                  _photos.remove(id);
                } else {
                  _photos[id] = v;
                }
                _photoUrls[id] = null;
              });
              _savePhotoCache();
              _saveDraft();
            },
            onSubmit: () async {
              if (_requiresAttentionDetail(
                  _responses, _notes, _photos, _photoUrls)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Monitor and Action items need a note or photo.'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              await _savePhotoCache();
              final photoUrls = await _uploadChecklistPhotos();
              _photoUrls
                ..clear()
                ..addAll(photoUrls);
              await _savePhotoCache();
              await _saveDraft();
              final List<ChecklistItem> items = snapshotItems ??
                  await ref.read(
                      checklistItemsProvider(_selectedTemplate!.id).future);
              if (widget.clientHistoryOnly) {
                await ref.read(clientChecklistSubmissionProvider).submit(
                      assetId: widget.assetId!,
                      clientId: widget.assetClientId!,
                      submittedBy: profile?.id ?? '',
                      submittedByRole: profile?.role.name,
                      template: _selectedTemplate!,
                      items: items,
                      responses: _responses,
                      notes: _notes,
                      photoUrls: photoUrls,
                      submittedAt: _completedAt,
                      currentHours: _currentHours,
                      generalNotes: _generalNotes,
                    );
              } else {
                await ref.read(maintenanceChecklistSubmissionProvider).submit(
                      workOrderId: widget.workOrderId!,
                      assetId: workOrder?.assetId,
                      clientId: workOrder?.clientId,
                      template: _selectedTemplate!,
                      loadItems: () async => items,
                      completedBy: profile?.id ?? '',
                      submittedByRole: profile?.role.name,
                      submittedAt: _completedAt,
                      responses: _responses,
                      notes: _notes,
                      photoUrls: photoUrls,
                      currentHours: _currentHours,
                      generalNotes: _generalNotes,
                      holdForSyncReason: _photoUploadDeferredReason,
                    );
                final submitState = ref.read(checklistControllerProvider);
                if (submitState.hasError) {
                  final error = submitState.error;
                  if (context.mounted) {
                    final savedLocally =
                        error is LocalChecklistPendingException;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(savedLocally
                            ? error.message
                            : 'Checklist save failed: $error'),
                        backgroundColor:
                            savedLocally ? AppColors.warning : AppColors.error,
                      ),
                    );
                  }
                  return;
                }
              }
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(_draftKey);
              await prefs.remove(_photoCacheKey);
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

bool _requiresAttentionDetail(
  Map<String, String?> responses,
  Map<String, String> notes,
  Map<String, Uint8List?> photos,
  Map<String, String?> photoUrls,
) {
  for (final entry in responses.entries) {
    final status = entry.value;
    if (status != 'monitor' && status != 'alert' && status != 'action') {
      continue;
    }
    final hasNote = notes[entry.key]?.trim().isNotEmpty == true;
    final hasLocalPhoto = photos[entry.key] != null;
    final hasUploadedPhoto = photoUrls[entry.key]?.isNotEmpty == true;
    if (!hasNote && !hasLocalPhoto && !hasUploadedPhoto) return true;
  }
  return false;
}

String _formatChecklistDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class _ChecklistRunHeader extends StatelessWidget {
  final String assetLabel;
  final String checklistLabel;
  final String completedByLabel;
  final DateTime completedAt;
  final TextEditingController hoursController;
  final TextEditingController notesController;
  final VoidCallback onPickCompletedAt;
  final ValueChanged<double?> onHoursChanged;
  final ValueChanged<String?> onNotesChanged;

  const _ChecklistRunHeader({
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
          _HeaderText(label: 'Asset', value: assetLabel),
          _HeaderText(label: 'Checklist', value: checklistLabel),
          _HeaderText(label: 'Completed by', value: completedByLabel),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Date/time'),
            subtitle: Text(_formatChecklistDateTime(completedAt)),
            trailing: const Icon(Icons.edit_calendar, size: 18),
            onTap: onPickCompletedAt,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: hoursController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Current hours (optional)',
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      onHoursChanged(double.tryParse(value.trim())),
                ),
              ),
            ],
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

class _HeaderText extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child:
          Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _GroupedTemplateSelector extends StatelessWidget {
  final List<ChecklistTemplate> templates;
  final ChecklistTemplate? preselected;
  final String emptyMessage;
  final ValueChanged<ChecklistTemplate> onSelect;

  const _GroupedTemplateSelector({
    required this.templates,
    this.preselected,
    required this.emptyMessage,
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
      ...grouped.keys
          .where((k) => !['pre_ops', 'general', 'dredge'].contains(k)),
    ];

    final categoryLabel = {
      'pre_ops': 'Pre-Operations',
      'general': 'General',
      'dredge': 'Dredge',
    };

    if (templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

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
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  color: preselected?.id == t.id
                      ? AppColors.primary.withValues(alpha: 0.08)
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
                        ? Text(t.description!,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: preselected?.id == t.id
                        ? const Icon(Icons.check,
                            color: AppColors.primary, size: 20)
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
  final bool showSyncStatus;
  final List<ChecklistItem>? snapshotItems;
  final String? metadataCaption;
  final Map<String, String?> responses;
  final Map<String, String> notes;
  final Map<String, Uint8List?> photos;
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
  final void Function(String id, Uint8List? photo) onPhotoChanged;
  final VoidCallback onSubmit;

  const _ChecklistForm({
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
    required this.onPhotoChanged,
    required this.onSubmit,
  });

  @override
  ConsumerState<_ChecklistForm> createState() => _ChecklistFormState();
}

class _ChecklistFormState extends ConsumerState<_ChecklistForm> {
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
    final itemsAsync = widget.snapshotItems != null
        ? AsyncValue.data(widget.snapshotItems!)
        : ref.watch(checklistItemsProvider(widget.template.id));
    final isLoading = ref.watch(checklistControllerProvider).isLoading;
    final syncStatusByItem = widget.showSyncStatus
        ? ref
                .watch(checklistResponseSyncStatusByItemProvider(
                    widget.workOrderId))
                .valueOrNull ??
            const <String, String>{}
        : const <String, String>{};
    final visibleSyncStatuses = syncStatusByItem.values
        .where(_isVisibleChecklistSyncStatus)
        .toList(growable: false);
    final hasSyncConflict = visibleSyncStatuses.contains(
      SyncStatusValues.conflict,
    );

    final headerWidgets = [
      _ChecklistRunHeader(
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
      // Template header
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
        _ChecklistSyncStatusBanner(hasConflict: hasSyncConflict),
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
                        _ChecklistItemWidget(
                          item: item,
                          status: widget.responses[item.id],
                          note: widget.notes[item.id] ?? '',
                          photo: widget.photos[item.id],
                          photoUrl: widget.photoUrls[item.id],
                          syncStatus: syncStatusByItem[item.id],
                          onStatusChanged: (v) =>
                              widget.onResponseChanged(item.id, v),
                          onNoteChanged: (v) =>
                              widget.onNoteChanged(item.id, v),
                          onPhotoChanged: (v) =>
                              widget.onPhotoChanged(item.id, v),
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

bool _isVisibleChecklistSyncStatus(String status) =>
    status != SyncStatusValues.synced;

String? _syncStatusChipLabel(String? status) {
  switch (status) {
    case SyncStatusValues.pendingCreate:
    case SyncStatusValues.pendingUpdate:
    case SyncStatusValues.pendingDelete:
    case SyncStatusValues.syncing:
      return 'Pending sync';
    case SyncStatusValues.failed:
      return 'Sync failed';
    case SyncStatusValues.conflict:
      return 'Conflict';
    default:
      return null;
  }
}

class _ChecklistSyncStatusBanner extends StatelessWidget {
  final bool hasConflict;

  const _ChecklistSyncStatusBanner({required this.hasConflict});

  @override
  Widget build(BuildContext context) {
    final color = hasConflict ? AppColors.error : AppColors.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            hasConflict ? Icons.sync_problem : Icons.cloud_off,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasConflict
                  ? 'Checklist has sync conflicts.'
                  : 'Saved locally. Sync pending.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistPhotoPreview extends StatelessWidget {
  final Uint8List? photo;
  final String? photoUrl;

  const _ChecklistPhotoPreview({
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
      return const _ChecklistPhotoPlaceholder();
    }

    return Image.network(
      url,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _ChecklistPhotoPlaceholder(),
    );
  }
}

class _ChecklistPhotoPlaceholder extends StatelessWidget {
  const _ChecklistPhotoPlaceholder();

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

class _ChecklistItemSyncChip extends StatelessWidget {
  final String syncStatus;

  const _ChecklistItemSyncChip({required this.syncStatus});

  @override
  Widget build(BuildContext context) {
    final label = _syncStatusChipLabel(syncStatus);
    if (label == null) return const SizedBox.shrink();

    final isError = syncStatus == SyncStatusValues.failed ||
        syncStatus == SyncStatusValues.conflict;
    final color = isError ? AppColors.error : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ChecklistItemWidget extends StatefulWidget {
  final ChecklistItem item;
  final String? status; // 'pass', 'monitor', 'action', 'n/a', or null
  final String note;
  final Uint8List? photo;
  final String? photoUrl;
  final String? syncStatus;
  final void Function(String? v) onStatusChanged;
  final void Function(String v) onNoteChanged;
  final void Function(Uint8List? v) onPhotoChanged;

  const _ChecklistItemWidget({
    required this.item,
    required this.status,
    required this.note,
    required this.photo,
    required this.photoUrl,
    required this.syncStatus,
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
  void didUpdateWidget(covariant _ChecklistItemWidget oldWidget) {
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
      widget.onPhotoChanged(bytes);
    }
  }

  Future<void> _takePhoto() async {
    final file =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (file != null) {
      final bytes = await file.readAsBytes();
      widget.onPhotoChanged(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final showDetail =
        status == 'alert' || status == 'monitor' || status == 'action';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item description
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(widget.item.descriptionEn,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (_syncStatusChipLabel(widget.syncStatus) != null) ...[
                  const SizedBox(width: 8),
                  _ChecklistItemSyncChip(syncStatus: widget.syncStatus!),
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

            // Answer buttons: PASS / MONITOR / ACTION / N/A
            Row(
              children: [
                _StatusButton(
                  label: 'PASS',
                  value: 'pass',
                  current: status,
                  color: AppColors.success,
                  onTap: () =>
                      widget.onStatusChanged(status == 'pass' ? null : 'pass'),
                ),
                const SizedBox(width: 8),
                _StatusButton(
                  label: 'MONITOR',
                  value: 'monitor',
                  current: status,
                  color: AppColors.warning,
                  onTap: () => widget.onStatusChanged(
                    status == 'monitor' || status == 'alert' ? null : 'monitor',
                  ),
                ),
                const SizedBox(width: 8),
                _StatusButton(
                  label: 'ACTION',
                  value: 'action',
                  current: status,
                  color: AppColors.error,
                  onTap: () => widget
                      .onStatusChanged(status == 'action' ? null : 'action'),
                ),
                const SizedBox(width: 8),
                _StatusButton(
                  label: 'N/A',
                  value: 'n/a',
                  current: status,
                  color: AppColors.textSecondary,
                  onTap: () =>
                      widget.onStatusChanged(status == 'n/a' ? null : 'n/a'),
                ),
              ],
            ),

            // Comment + photo — only prompt for monitor/action follow-up.
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
                        Row(
                          children: [
                            if (widget.photo != null ||
                                widget.photoUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: _ChecklistPhotoPreview(
                                  photo: widget.photo,
                                  photoUrl: widget.photoUrl,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    size: 16, color: AppColors.error),
                                onPressed: () => widget.onPhotoChanged(null),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                            ],
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
