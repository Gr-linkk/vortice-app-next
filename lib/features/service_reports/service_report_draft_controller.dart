import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/features/service_reports/service_report_draft_manager.dart';

class ServiceReportDraftController {
  ServiceReportDraftController({
    required this.initialWorkOrderId,
    this.accountId = 'signed_out',
    required this.complaintController,
    required this.causeController,
    required this.correctionController,
    required this.collateralController,
    required this.commentsController,
    required this.onStateChanged,
  }) : _draftManager = const ServiceReportDraftManager();

  final String? initialWorkOrderId;
  final String accountId;
  final TextEditingController complaintController;
  final TextEditingController causeController;
  final TextEditingController correctionController;
  final TextEditingController collateralController;
  final TextEditingController commentsController;
  final VoidCallback onStateChanged;

  final ServiceReportDraftManager _draftManager;
  Timer? _draftSaveDebounce;
  bool restoringDraft = false;

  String? selectedWorkOrderId;
  String? pendingReportId;
  Uint8List? signatureBytes;
  bool signatureSaved = false;
  final List<Uint8List> photos = [];

  String get draftKey => accountStorageKey(
    accountId,
    ServiceReportDraftKeys.draftKey(initialWorkOrderId),
  );
  String get draftMediaKey => accountStorageKey(
    accountId,
    ServiceReportDraftKeys.draftMediaKey(initialWorkOrderId),
  );

  Iterable<TextEditingController> get _textControllers => [
    complaintController,
    causeController,
    correctionController,
    collateralController,
    commentsController,
  ];

  void bindTextSaveListeners() {
    for (final controller in _textControllers) {
      controller.addListener(scheduleTextSave);
    }
  }

  void dispose() {
    final hasPendingText = _draftSaveDebounce?.isActive == true;
    _draftSaveDebounce?.cancel();
    // Capture controller values before the screen disposes them. Otherwise a
    // quick Back within the debounce window silently loses the last edit.
    if (hasPendingText) unawaited(saveText());
    for (final controller in _textControllers) {
      controller.removeListener(scheduleTextSave);
    }
  }

  Future<void> load() async {
    restoringDraft = true;
    try {
      final draft = await _draftManager.load(
        draftKey: draftKey,
        draftMediaKey: draftMediaKey,
      );
      if (draft == null) return;

      selectedWorkOrderId = draft.workOrderId;
      pendingReportId = draft.pendingReportId;
      complaintController.text = draft.complaint;
      causeController.text = draft.cause;
      correctionController.text = draft.correction;
      collateralController.text = draft.collateral;
      commentsController.text = draft.comments;
      if (draft.signatureBytes != null) {
        signatureBytes = Uint8List.fromList(draft.signatureBytes!);
        signatureSaved = true;
      }
      photos
        ..clear()
        ..addAll(draft.photos.map(Uint8List.fromList));
      onStateChanged();
    } finally {
      restoringDraft = false;
    }
  }

  void scheduleTextSave() {
    if (restoringDraft) return;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(saveText());
    });
  }

  Future<void> saveAll() async {
    _draftSaveDebounce?.cancel();
    await saveText();
    await saveMedia();
  }

  Future<void> saveText() async {
    if (restoringDraft) return;
    await _draftManager.saveText(
      draftKey: draftKey,
      workOrderId: selectedWorkOrderId,
      pendingReportId: pendingReportId,
      complaint: complaintController.text,
      cause: causeController.text,
      correction: correctionController.text,
      collateral: collateralController.text,
      comments: commentsController.text,
    );
  }

  Future<void> saveMedia() async {
    if (restoringDraft) return;
    await _draftManager.saveMedia(
      draftMediaKey: draftMediaKey,
      signatureBytes: signatureBytes,
      photos: photos.map((photo) => photo.toList()).toList(),
    );
  }

  Future<void> clear() {
    _draftSaveDebounce?.cancel();
    return _draftManager.clear(
      draftKey: draftKey,
      draftMediaKey: draftMediaKey,
    );
  }

  void resetAfterSubmit() {
    selectedWorkOrderId = null;
    pendingReportId = null;
    signatureBytes = null;
    signatureSaved = false;
    photos.clear();
  }
}
