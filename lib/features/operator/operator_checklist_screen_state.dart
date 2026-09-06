import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
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
  late final String _accountId;
  String _operationId = const Uuid().v4();
  Future<void> _draftWrite = Future.value();
  String get _draftKey =>
      accountStorageKey(_accountId, operatorChecklistDraftKey);

  @override
  void initState() {
    super.initState();
    _accountId = ref.read(sessionProvider)?.user.id ?? 'signed_out';
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
        _operationId = data['operation_id'] as String? ?? _operationId;
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
        await prefs.remove(_draftKey);
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

  Future<void> _saveDraft() {
    final raw = jsonEncode({
      ...encodeOperatorChecklistDraft(
        asset: _selectedAsset,
        template: _selectedTemplate,
        responses: _responses,
        notes: _notes,
        completedAt: _completedAt,
        currentHours: _currentHours,
        generalNotes: _generalNotes,
        photos: _photos,
      ),
      'operation_id': _operationId,
    });
    _draftWrite = _draftWrite.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, raw);
    });
    return _draftWrite;
  }

  Future<void> _clearDraft() async {
    await _draftWrite;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  void _resetChecklist() {
    setState(() {
      _operationId = const Uuid().v4();
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
      final items = await ref.read(
        checklistItemsProvider(_selectedTemplate!.id).future,
      );
      if (!mounted || ref.read(sessionProvider)?.user.id != _accountId) {
        throw const AccountChangedException();
      }
      await ref
          .read(operationsChecklistSubmissionProvider)
          .submit(
            operationId: _operationId,
            photos: _photos,
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

      await _clearDraft();
      if (mounted) {
        final queued = (await ref.read(fieldWorkQueueProvider)?.list() ?? [])
            .where((r) => r.id == _operationId)
            .firstOrNull;
        if (!mounted) return;
        final es = Localizations.localeOf(context).languageCode == 'es';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued?.synced == true
                  ? AppLocalizations.of(context).checklistSubmitted
                  : queued?.needsAttention == true
                  ? (es
                        ? 'Guardado; necesita atención. Abre sincronización.'
                        : 'Saved; needs attention. Open sync status.')
                  : (es
                        ? 'Guardado en este dispositivo; pendiente de envío.'
                        : 'Saved on this device; pending upload.'),
            ),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _operationId = const Uuid().v4();
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
    } on OperationsChecklistValidationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message(
                Localizations.localeOf(context).languageCode == 'es',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
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
