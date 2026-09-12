import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/checklists/asset_checklist_template_filter.dart';
import 'package:uuid/uuid.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'operator_checklist_draft_store.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late final OperatorChecklistDraftStore _draftStore;
  List<Map<String, dynamic>> _drafts = [];
  bool _restoring = false;
  bool _showDrafts = true;
  String? _assignmentId;
  String? _draftError;
  bool get _sameAccount =>
      mounted && ref.read(sessionProvider)?.user.id == _accountId;
  @override
  void initState() {
    super.initState();
    _accountId = ref.read(sessionProvider)?.user.id ?? 'signed_out';
    _assignmentId = widget.initialAssignmentId;
    final container = ProviderScope.containerOf(context, listen: false);
    _draftStore = OperatorChecklistDraftStore(
      _accountId,
      () => container.read(sessionProvider)?.user.id,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraftIfReady());
  }

  Future<void> _restoreDraftIfReady() async {
    if (_restoredDraft || _restoring) return;
    final assets = ref.read(operatorAssignedAssetsProvider).valueOrNull;
    final templates = ref.read(checklistTemplatesProvider).valueOrNull;
    if (assets == null || templates == null) return;
    _restoring = true;
    try {
      final drafts = await _draftStore.list();
      if (!_sameAccount) return;
      _drafts = drafts;
      if (widget.initialAssignmentId != null) {
        final draft = drafts
            .where((d) => d['assignment_id'] == widget.initialAssignmentId)
            .firstOrNull;
        await _openAssignment(widget.initialAssignmentId!, draft: draft);
      } else if (widget.initialAssetId != null) {
        final asset = assets
            .where((a) => a['id'] == widget.initialAssetId)
            .firstOrNull;
        if (asset == null) {
          _selectionError = 'asset';
        } else {
          // An asset deep link is explicit; an unrelated saved run never wins.
          _showDrafts = false;
          _chooseAsset(asset, initialTemplateId: widget.initialTemplateId);
        }
      }
    } catch (_) {
      if (_sameAccount) _draftError = 'load';
    } finally {
      _restoring = false;
      if (_sameAccount) setState(() => _restoredDraft = true);
    }
  }

  Future<void> _openAssignment(
    String assignmentId, {
    Map<String, dynamic>? draft,
  }) async {
    try {
      final assignments = await ref.read(myChecklistAssignmentsProvider.future);
      if (!_sameAccount) return;
      final assignment = assignments
          .where((a) => a['id'] == assignmentId)
          .firstOrNull;
      final assetId = (assignment?['assets'] as Map?)?['id'];
      final templateId = (assignment?['checklist_templates'] as Map?)?['id'];
      if (assignment == null ||
          !['pending', 'in_progress'].contains(assignment['status']) ||
          (draft != null &&
              (draft['assetId'] != assetId ||
                  draft['templateId'] != templateId))) {
        _selectionError = 'assignment';
        return;
      }
      if (draft != null) {
        _restoreRun(draft);
      } else {
        final assets =
            ref.read(operatorAssignedAssetsProvider).valueOrNull ?? [];
        final templates =
            ref.read(checklistTemplatesProvider).valueOrNull ?? [];
        _selectedAsset = assets.where((a) => a['id'] == assetId).firstOrNull;
        _selectedTemplate = templates
            .where((t) => t.id == templateId)
            .firstOrNull;
        if (_selectedAsset == null ||
            _selectedTemplate == null ||
            !_templateMatches(
              _selectedTemplate!,
              _selectedAsset!,
              pinned: true,
            )) {
          _selectionError = 'assignment';
          return;
        }
        _assignmentId = assignmentId;
        await _saveDraft();
      }
      _showDrafts = false;
    } catch (error) {
      // Only a connection failure may resume the already-started pinned run.
      // Permission failures and revoked assignments never fall back to a draft.
      if (_sameAccount && isConnectionFailure(error) && draft != null) {
        _restoreRun(draft);
        _showDrafts = false;
      } else if (_sameAccount) {
        _selectionError = 'assignment';
      }
    }
  }

  bool _templateMatches(
    ChecklistTemplate template,
    Map<String, dynamic> asset, {
    bool pinned = false,
  }) => checklistTemplateMatches(
    pinned ? template.copyWith(isActive: true) : template,
    kind: 'operator_daily',
    assetId: asset['id'] as String?,
    assetTypeId: asset['asset_type_id'] as String?,
    clientId: asset['client_id'] as String?,
  );

  bool _draftAvailable(Map<String, dynamic> draft) {
    final assets = ref.read(operatorAssignedAssetsProvider).valueOrNull ?? [];
    final templates = ref.read(checklistTemplatesProvider).valueOrNull ?? [];
    final asset = assets.where((a) => a['id'] == draft['assetId']).firstOrNull;
    final template = templates
        .where((t) => t.id == draft['templateId'])
        .firstOrNull;
    return asset != null &&
        template != null &&
        _templateMatches(template, asset, pinned: true);
  }

  void _restoreRun(Map<String, dynamic> draft) {
    if (!_sameAccount || !_draftAvailable(draft)) {
      _selectionError = 'asset';
      return;
    }
    final restored = decodeOperatorChecklistDraft(
      draft,
      fallbackCompletedAt: DateTime.now(),
      assets: ref.read(operatorAssignedAssetsProvider).valueOrNull,
      templates: ref.read(checklistTemplatesProvider).valueOrNull ?? [],
    );
    _operationId = draft['operation_id'] as String;
    _assignmentId = draft['assignment_id'] as String?;
    _selectedAsset = restored.asset;
    _selectedTemplate = restored.template;
    _completedAt = restored.completedAt;
    _startedAt =
        DateTime.tryParse(draft['started_at'] as String? ?? '') ??
        restored.completedAt;
    _currentHours = restored.currentHours;
    _generalNotes = restored.generalNotes;
    _responses
      ..clear()
      ..addAll(restored.responses);
    _notes
      ..clear()
      ..addAll(restored.notes);
    _photos
      ..clear()
      ..addAll(restored.photos);
  }

  Future<void> _resumeDraft(Map<String, dynamic> draft) async {
    if (!_sameAccount || _restoring) return;
    setState(() => _restoring = true);
    try {
      final assignment = draft['assignment_id'] as String?;
      if (assignment == null) {
        _restoreRun(draft);
        _showDrafts = false;
      } else {
        await _openAssignment(assignment, draft: draft);
      }
    } catch (_) {
      if (_sameAccount) _draftError = 'load';
    } finally {
      if (_sameAccount) setState(() => _restoring = false);
    }
  }

  void _chooseAsset(Map<String, dynamic> asset, {String? initialTemplateId}) {
    final templates = ref.read(checklistTemplatesProvider).valueOrNull ?? [];
    final matching = operatorTemplatesForAsset(asset, templates);
    setState(() {
      _selectedAsset = asset;
      _selectedTemplate = initialTemplateId == null
          ? (matching.length == 1 ? matching.single : null)
          : matching.where((t) => t.id == initialTemplateId).firstOrNull;
      _responses.clear();
      _notes.clear();
      _photos.clear();
      _startedAt = DateTime.now();
      _completedAt = _startedAt;
    });
    unawaited(_saveDraft());
  }

  Future<void> _saveDraft() {
    if (!_sameAccount || _selectedAsset == null || _selectedTemplate == null) {
      return Future.value();
    }
    final data = <String, dynamic>{
      ...encodeOperatorChecklistDraft(
        asset: _selectedAsset,
        template: _selectedTemplate,
        responses: Map.of(_responses),
        notes: Map.of(_notes),
        completedAt: _completedAt,
        currentHours: _currentHours,
        generalNotes: _generalNotes,
        photos: Map.of(_photos),
      ),
      'operation_id': _operationId,
      'assignment_id': _assignmentId,
      'started_at': _startedAt.toUtc().toIso8601String(),
    };
    // Serialize writes; an earlier delayed save cannot overwrite newer input.
    final write = _draftWrite.then((_) => _draftStore.save(data)).then((_) {
      if (_sameAccount && _draftError == 'save') {
        setState(() => _draftError = null);
      }
    });
    _draftWrite = write.catchError((Object error) {
      if (_sameAccount) setState(() => _draftError = 'save');
    });
    return _draftWrite;
  }

  Future<void> _clearDraft() async {
    await _draftWrite;
    await _draftStore.remove(_operationId);
    _drafts = await _draftStore.list();
  }

  Future<void> _resetChecklist() async {
    await _saveDraft();
    if (!_sameAccount || _draftError == 'save') return;
    final drafts = await _draftStore.list();
    if (!_sameAccount) return;
    setState(() {
      _drafts = drafts;
      _showDrafts = false;
      _assignmentId = null;
      _operationId = const Uuid().v4();
      _selectedAsset = null;
      _selectedTemplate = null;
      _responses.clear();
      _notes.clear();
      _photos.clear();
      _completedAt = DateTime.now();
      _startedAt = _completedAt;
      _currentHours = null;
      _generalNotes = null;
    });
  }

  String _draftSubtitle(BuildContext context, Map<String, dynamic> draft) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final template = ref
        .read(checklistTemplatesProvider)
        .valueOrNull!
        .firstWhere((template) => template.id == draft['templateId']);
    final started = DateTime.tryParse(
      '${draft['started_at'] ?? ''}',
    )?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final startedLabel = started == null
        ? (es ? 'Hora de inicio no registrada' : 'Start time not recorded')
        : '${es ? 'Iniciada' : 'Started'} ${localizations.formatShortDate(started)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(started))}';
    return '${template.name} · v${template.version}\n$startedLabel\n${es ? 'Guardado en este dispositivo' : 'Saved on this device'}';
  }

  Widget _draftChoices(BuildContext context) {
    final es = Localizations.localeOf(context).languageCode == 'es';
    final assets = ref.read(operatorAssignedAssetsProvider).valueOrNull ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          es ? 'Listas sin terminar' : 'Unfinished checklists',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final draft in _drafts.where(_draftAvailable))
          Card(
            child: ListTile(
              leading: const Icon(Icons.restore),
              title: Text(
                es
                    ? 'Continuar lista de ${assets.firstWhere((a) => a['id'] == draft['assetId'])['name']}'
                    : 'Resume ${assets.firstWhere((a) => a['id'] == draft['assetId'])['name']} checklist',
              ),
              subtitle: Text(_draftSubtitle(context, draft)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _resumeDraft(draft),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() => _showDrafts = false),
          icon: const Icon(Icons.add),
          label: Text(es ? 'Iniciar otra lista' : 'Start another checklist'),
        ),
      ],
    );
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

    final es = Localizations.localeOf(context).languageCode == 'es';
    if (ref.watch(sessionProvider)?.user.id != _accountId) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.operatorChecklistTitle)),
        body: Center(
          child: Text(
            es
                ? 'La cuenta cambió. Vuelve a abrir esta pantalla.'
                : 'The account changed. Reopen this screen.',
          ),
        ),
      );
    }
    if (assetsAsync.hasError ||
        templatesAsync.hasError ||
        _draftError == 'load') {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.operatorChecklistTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  es
                      ? 'No se pudieron cargar los equipos y las listas guardadas.'
                      : 'Equipment and saved checklists could not be loaded.',
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _restoredDraft = false;
                      _draftError = null;
                    });
                    ref.invalidate(operatorAssignedAssetsProvider);
                    ref.invalidate(checklistTemplatesProvider);
                    unawaited(_restoreDraftIfReady());
                  },
                  child: Text(es ? 'Reintentar' : 'Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_restoredDraft || _restoring) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.operatorChecklistTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.operatorChecklistTitle)),
      body: _draftError == 'save'
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    es
                        ? 'No se pudo guardar la lista. Mantén esta pantalla abierta.'
                        : 'The checklist could not be saved. Keep this screen open.',
                  ),
                  TextButton(
                    onPressed: _saveDraft,
                    child: Text(es ? 'Reintentar' : 'Try again'),
                  ),
                ],
              ),
            )
          : _selectionError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Localizations.localeOf(context).languageCode == 'es'
                          ? 'Esta revisión asignada ya no está disponible. Revisa el historial o pide al responsable una nueva asignación.'
                          : 'This equipment or assignment is no longer available. Your draft is kept. Ask your manager to check access.',
                    ),
                    TextButton(
                      onPressed: () => context.go('/client/dashboard'),
                      child: Text(l10n.back),
                    ),
                  ],
                ),
              ),
            )
          : _showDrafts && _drafts.any(_draftAvailable)
          ? _draftChoices(context)
          : _selectedAsset == null || _selectedTemplate == null
          ? OperatorChecklistSelectionStep(
              assetsAsync: assetsAsync,
              templatesAsync: templatesAsync,
              selectedAsset: _selectedAsset,
              selectedTemplate: _selectedTemplate,
              onAssetSelected: _chooseAsset,
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
              key: ValueKey(_operationId),
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
    if (!_sameAccount || _draftError == 'save') return;
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
            assignmentId: _assignmentId,
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
        if (!mounted || ref.read(sessionProvider)?.user.id != _accountId) {
          return;
        }
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
        if (_assignmentId != null) {
          context.go('/client/dashboard');
          return;
        }
        setState(() {
          _operationId = const Uuid().v4();
          _assignmentId = null;
          _showDrafts = true;
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
