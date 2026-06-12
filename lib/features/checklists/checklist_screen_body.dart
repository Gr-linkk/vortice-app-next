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
import 'package:vortice_app/features/checklists/checklist_submission_orchestrator.dart';
import 'package:vortice_app/features/checklists/checklist_support.dart';
import 'package:vortice_app/features/checklists/checklist_template_selector.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/checklist_item.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/sync/sync_status.dart';

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
      jsonEncode(
        encodeChecklistDraft(
          templateId: _selectedTemplate?.id ?? _draftTemplateId,
          responses: _responses,
          notes: _notes,
          photoUrls: _photoUrls,
          completedAt: _completedAt,
          currentHours: _currentHours,
          generalNotes: _generalNotes,
          photos: _photos,
        ),
      ),
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

          return ChecklistForm(
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
              if (requiresAttentionDetail(
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
