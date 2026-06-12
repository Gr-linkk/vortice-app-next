import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:vortice_app/features/checklists/checklist_form.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/checklist_repository.dart';
import 'package:vortice_app/features/checklists/checklist_screen_support.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/features/checklists/checklist_template_selector.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';

class ChecklistScreenBody extends ConsumerStatefulWidget {
  final String? workOrderId;
  final String? assetId;
  final String? assetClientId;
  final String? assetName;
  final String? assetTypeId;
  final bool clientHistoryOnly;
  final String? preSelectedTemplateId;

  const ChecklistScreenBody({
    super.key,
    required this.workOrderId,
    required this.assetId,
    required this.assetClientId,
    required this.assetName,
    required this.assetTypeId,
    required this.clientHistoryOnly,
    required this.preSelectedTemplateId,
  });

  @override
  ConsumerState<ChecklistScreenBody> createState() =>
      _ChecklistScreenBodyState();
}

class _ChecklistScreenBodyState extends ConsumerState<ChecklistScreenBody> {
  ChecklistTemplate? _selectedTemplate;
  String? _draftTemplateId;
  bool _showPicker = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSavedChecklistState();
      if (widget.preSelectedTemplateId != null) {
        await _loadPreSelectedTemplate();
      }
    });
  }

  String get _checklistRunKey => checklistRunKey(
        workOrderId: widget.workOrderId,
        assetId: widget.assetId,
      );

  String get _draftKey => checklistDraftKey(_checklistRunKey);
  String get _photoCacheKey => checklistPhotoCacheKey(_checklistRunKey);

  Future<void> _loadCachedPhotos(SharedPreferences prefs) async {
    final raw = prefs.getString(_photoCacheKey);
    if (raw == null) return;
    final decoded = decodePhotoCacheJson(raw);
    if (decoded.isEmpty && raw.isNotEmpty) {
      await prefs.remove(_photoCacheKey);
      return;
    }
    _photos.addAll(decoded);
  }

  Future<void> _savePhotoCache() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = encodePhotoCache(_photos);

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
        final saved = savedResponsesFromWorkOrder(savedResponses);
        _responses.addAll(saved.responses);
        _notes.addAll(saved.notes);
        _photoUrls.addAll(saved.photoUrls);
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
        final restored = decodeChecklistDraftJson(
          data,
          fallbackCompletedAt: _completedAt,
        );
        _draftTemplateId = restored.templateId;
        _completedAt = restored.completedAt;
        _currentHours = restored.currentHours;
        _generalNotes = restored.generalNotes;
        _responses.addAll(restored.responses);
        _notes.addAll(restored.notes);
        _photoUrls.addAll(restored.photoUrls);
        _photos.addAll(restored.photos);
        restoredDraftPhotos = restored.restoredDraftPhotos;
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
      checklistDraftJson(
        templateId: _selectedTemplate?.id ?? _draftTemplateId,
        responses: _responses,
        notes: _notes,
        photoUrls: _photoUrls,
        completedAt: _completedAt,
        currentHours: _currentHours,
        generalNotes: _generalNotes,
        photos: _photos,
      ),
    );
  }

  Future<Map<String, String?>> _uploadChecklistPhotos() async {
    final result = await uploadPendingChecklistPhotos(
      photos: _photos,
      existingUrls: _photoUrls,
      upload: (itemId, bytes) async {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final path = 'checklists/$_checklistRunKey/${itemId}_$ts.jpg';
        await supabase.storage
            .from(AppConstants.bucketReportPhotos)
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            )
            .timeout(const Duration(seconds: 4));
        return supabase.storage
            .from(AppConstants.bucketReportPhotos)
            .getPublicUrl(path);
      },
    );
    _photoUploadDeferredReason = result.deferredReason;
    return result.urls;
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

          final selection = resolveChecklistTemplateSelection(
            currentSelected: _selectedTemplate,
            currentDraftTemplateId: _draftTemplateId,
            currentShowPicker: _showPicker,
            snapshot: snapshot,
            boundTemplateId: boundTemplateId,
            templates: templates,
          );
          _selectedTemplate = selection.selected;
          _draftTemplateId = selection.draftTemplateId;
          _showPicker = selection.showPicker;

          if (shouldShowChecklistTemplatePicker(
            templateSelectionLocked: templateSelectionLocked,
            showPicker: _showPicker,
            selectedTemplate: _selectedTemplate,
          )) {
            return ChecklistTemplateSelector(
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

          final snapshotItems = snapshotItemsForTemplate(
            snapshot: snapshot,
            selectedTemplate: _selectedTemplate!,
          );

          return ChecklistForm(
            template: _selectedTemplate!,
            workOrderId: _checklistRunKey,
            showSyncStatus: widget.workOrderId != null,
            snapshotItems: snapshotItems,
            metadataCaption: buildChecklistMetadataCaption(
              snapshot: snapshot,
              snapshotItems: snapshotItems,
            ),
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
            onSubmit: () => _submitChecklist(context, l10n, snapshotItems),
          );
        },
      ),
    );
  }

  Future<void> _submitChecklist(
    BuildContext context,
    AppLocalizations l10n,
    List<ChecklistItem>? snapshotItems,
  ) async {
    if (requiresAttentionDetail(_responses, _notes, _photos, _photoUrls)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monitor and Action items need a note or photo.'),
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
    final profile = ref.read(profileProvider).valueOrNull;
    final workOrder = widget.workOrderId == null
        ? null
        : ref.read(workOrderByIdProvider(widget.workOrderId!)).valueOrNull;
    final List<ChecklistItem> items = snapshotItems ??
        await ref.read(checklistItemsProvider(_selectedTemplate!.id).future);
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
          final savedLocally = error is LocalChecklistPendingException;
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
  }
}
