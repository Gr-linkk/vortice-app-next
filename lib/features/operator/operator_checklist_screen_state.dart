import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/features/operator/operator_checklist_run_form.dart';
import 'package:vortice_app/features/operator/operator_checklist_screen.dart';
import 'package:vortice_app/features/operator/operator_checklist_selection_step.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_template.dart';

class OperatorChecklistScreenState
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
    if (templates == null) {
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
        final photos =
            (data['photos'] as Map?)?.cast<String, dynamic>() ?? {};
        final completedAtRaw = data['completedAt'] as String?;
        if (completedAtRaw != null) {
          _completedAt = DateTime.tryParse(completedAtRaw) ?? _completedAt;
        }
        _currentHours = (data['currentHours'] as num?)?.toDouble();
        _generalNotes = data['generalNotes'] as String?;

        final savedAsset = data['asset'];
        assetToSet = assetId == null
            ? null
            : assets?.where((r) => r['id'] == assetId).firstOrNull;
        if (assetToSet == null && savedAsset is Map) {
          assetToSet = savedAsset.cast<String, dynamic>();
        }
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
          assets?.where((r) => r['id'] == widget.initialAssetId).firstOrNull;
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
        'asset': _selectedAsset,
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
          ? OperatorChecklistSelectionStep(
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
          : OperatorChecklistRunForm(
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
      if (requiresAttentionDetail(_responses, _notes, _photos, const {})) {
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
      final items =
          await ref.read(checklistItemsProvider(_selectedTemplate!.id).future);
      await ref.read(operationsChecklistSubmissionProvider).submit(
            assetId: _selectedAsset!['id'] as String,
            assetClientId: _selectedAsset!['client_id'] as String?,
            operatorId: profile?.id,
            submittedByRole: profile?.role.name,
            runType: _runType,
            template: _selectedTemplate!,
            items: items,
            responses: _responses,
            notes: _notes,
            submittedAt: _completedAt,
            currentHours: _currentHours,
            generalNotes: _generalNotes,
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
