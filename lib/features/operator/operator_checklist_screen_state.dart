import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  String? _selectionError;
  DateTime _completedAt = DateTime.now();
  double? _currentHours;
  String? _generalNotes;
  late final String _accountId;
  String _operationId = const Uuid().v4();
  late DateTime _startedAt = _completedAt;
  Future<void> _draftWrite = Future.value();
  String get _draftKey => accountStorageKey(
    _accountId,
    widget.initialAssignmentId == null
        ? operatorChecklistDraftKey
        : '$operatorChecklistDraftKey:${widget.initialAssignmentId}',
  );

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
    if (templates == null || assets == null) {
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
        _startedAt =
            DateTime.tryParse(data['started_at'] as String? ?? '') ??
            restored.completedAt;
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
    if (widget.initialAssignmentId != null) {
      try {
        final assignments = await ref.read(
          myChecklistAssignmentsProvider.future,
        );
        final assignment = assignments
            .where((a) => a['id'] == widget.initialAssignmentId)
            .firstOrNull;
        if (assignment == null ||
            !['pending', 'in_progress'].contains(assignment['status'])) {
          _selectionError = 'assignment';
        } else {
          final assetId = (assignment['assets'] as Map?)?['id'];
          final templateId = (assignment['checklist_templates'] as Map?)?['id'];
          assetToSet = assets.where((a) => a['id'] == assetId).firstOrNull;
          templateToSet = templates
              .where((t) => t.id == templateId)
              .firstOrNull;
          if (assetToSet == null || templateToSet == null) {
            _selectionError = 'assignment';
          }
        }
      } catch (_) {
        // A previously started assignment retains its pinned local draft.
        if (raw == null || assetToSet == null || templateToSet == null) {
          _selectionError = 'assignment';
        }
      }
    }
    if (templateToSet != null &&
        !checklistTemplateMatches(
          (raw != null || widget.initialAssignmentId != null)
              ? templateToSet.copyWith(isActive: true)
              : templateToSet,
          kind: 'operator_daily',
          assetId: assetToSet?['id'] as String?,
          assetTypeId: assetToSet?['asset_type_id'] as String?,
          clientId: assetToSet?['client_id'] as String?,
        )) {
      templateToSet = null;
      _responses.clear();
      _notes.clear();
      _photos.clear();
      if (widget.initialAssignmentId != null) _selectionError = 'assignment';
    }
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
      'started_at': _startedAt.toUtc().toIso8601String(),
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
    if (widget.initialAssignmentId != null) {
      context.go('/client/dashboard');
      return;
    }
    setState(() {
      _operationId = const Uuid().v4();
      _selectedAsset = null;
      _selectedTemplate = null;
      _responses.clear();
      _notes.clear();
      _photos.clear();
      _completedAt = DateTime.now();
      _startedAt = DateTime.now();
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
      body: _selectionError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Localizations.localeOf(context).languageCode == 'es'
                          ? 'Esta revisión asignada ya no está disponible. Revisa el historial o pide al responsable una nueva asignación.'
                          : 'This assignment is no longer available. Check its history or ask your manager for a new assignment.',
                    ),
                    TextButton(
                      onPressed: () => context.go('/client/dashboard'),
                      child: Text(l10n.back),
                    ),
                  ],
                ),
              ),
            )
          : _selectedAsset == null || _selectedTemplate == null
          ? OperatorChecklistSelectionStep(
              assetsAsync: assetsAsync,
              templatesAsync: templatesAsync,
              selectedAsset: _selectedAsset,
              selectedTemplate: _selectedTemplate,
              onAssetSelected: (a) {
                setState(() {
                  _selectedAsset = a;
                  _selectedTemplate = null;
                  _responses.clear();
                  _notes.clear();
                  _photos.clear();
                });
                _saveDraft();
              },
              onTemplateSelected: (t) {
                setState(() {
                  _selectedTemplate = t;
                  _startedAt = DateTime.now();
                  _completedAt = _startedAt;
                });
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
            assignmentId: widget.initialAssignmentId,
            startedAt: _startedAt.isAfter(_completedAt)
                ? _completedAt
                : _startedAt,
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
          ),
        );
        ref.invalidate(myChecklistAssignmentsProvider);
        if (widget.initialAssignmentId != null) {
          context.go('/client/dashboard');
          return;
        }
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
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(operatorOfflineSubmitMessage)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(operatorOfflineSubmitMessage)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
