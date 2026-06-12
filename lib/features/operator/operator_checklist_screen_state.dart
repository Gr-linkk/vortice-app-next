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
import 'package:vortice_app/features/operator/operator_checklist_support.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_template.dart';

class OperatorChecklistScreenState
    extends ConsumerState<OperatorChecklistScreen> {
  Map<String, dynamic>? _selectedAsset;
  ChecklistTemplate? _selectedTemplate;
  final String _runType = operatorDefaultRunType;
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
    final raw = prefs.getString(operatorChecklistDraftKey);

    Map<String, dynamic>? assetToSet = _selectedAsset;
    ChecklistTemplate? templateToSet = _selectedTemplate;

    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final restored = decodeOperatorChecklistDraft(
          data,
          fallbackCompletedAt: _completedAt,
          assets: assets,
          templates: templates,
        );
        assetToSet = restored.asset;
        templateToSet = restored.template;
        _completedAt = restored.completedAt;
        _currentHours = restored.currentHours;
        _generalNotes = restored.generalNotes;

        if (mounted) {
          setState(() {
            _selectedAsset = assetToSet;
            _selectedTemplate = templateToSet;
            _responses
              ..clear()
              ..addAll(restored.responses);
            _notes
              ..clear()
              ..addAll(restored.notes);
            _photos
              ..clear()
              ..addAll(restored.photos);
          });
        }
      } catch (_) {
        await prefs.remove(operatorChecklistDraftKey);
      }
    }

    assetToSet = resolveOperatorInitialAsset(
      currentAsset: assetToSet,
      initialAssetId: widget.initialAssetId,
      assets: assets,
    );
    templateToSet = resolveOperatorInitialTemplate(
      currentTemplate: templateToSet,
      initialTemplateId: widget.initialTemplateId,
      templates: templates,
    );
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
      operatorChecklistDraftKey,
      jsonEncode(
        encodeOperatorChecklistDraft(
          asset: _selectedAsset,
          template: _selectedTemplate,
          responses: _responses,
          notes: _notes,
          completedAt: _completedAt,
          currentHours: _currentHours,
          generalNotes: _generalNotes,
          photos: _photos,
        ),
      ),
    );
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(operatorChecklistDraftKey);
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

      final hasPhotos = operatorSubmissionHasPhotos(_photos);
      await _clearDraft();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasPhotos
                  ? operatorPhotoNotSubmittedMessage
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
            content: Text(operatorOfflineSubmitMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(operatorOfflineSubmitMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
