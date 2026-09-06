import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_action_bar.dart';
import 'package:vortice_app/features/service_reports/service_report_app_bar.dart';
import 'package:vortice_app/features/service_reports/service_report_draft_controller.dart';
import 'package:vortice_app/features/service_reports/service_report_form_body.dart';
import 'package:vortice_app/features/service_reports/service_report_media_section.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_screen.dart';
import 'package:vortice_app/features/service_reports/service_report_signature_sheet.dart';
import 'package:vortice_app/features/service_reports/service_report_submit_handler.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class ServiceReportScreenState extends ConsumerState<ServiceReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _complaintCtrl = TextEditingController();
  final _causeCtrl = TextEditingController();
  final _correctionCtrl = TextEditingController();
  final _collateralCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  final _submitHandler = const ServiceReportSubmitHandler();
  final _picker = ImagePicker();
  late final ServiceReportDraftController _draft;

  @override
  void initState() {
    super.initState();
    _draft = ServiceReportDraftController(
      accountId: ref.read(sessionProvider)?.user.id ?? 'signed_out',
      initialWorkOrderId: widget.initialWorkOrderId,
      complaintController: _complaintCtrl,
      causeController: _causeCtrl,
      correctionController: _correctionCtrl,
      collateralController: _collateralCtrl,
      commentsController: _commentsCtrl,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
    _draft.selectedWorkOrderId = widget.initialWorkOrderId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _draft.load();
      _draft.bindTextSaveListeners();
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    _complaintCtrl.dispose();
    _causeCtrl.dispose();
    _correctionCtrl.dispose();
    _collateralCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(Future<Uint8List?> Function() pick) async {
    final bytes = await pick();
    if (bytes == null) return;
    setState(() => _draft.photos.add(bytes));
    await _draft.saveAll();
  }

  Future<void> _submit() async {
    final result = await _submitHandler.submit(
      context: context,
      ref: ref,
      formKey: _formKey,
      input: ServiceReportSubmitInput(
        selectedWorkOrderId: _draft.selectedWorkOrderId,
        pendingReportId: _draft.pendingReportId,
        complaint: _complaintCtrl.text,
        cause: _causeCtrl.text,
        correction: _correctionCtrl.text,
        collateral: _collateralCtrl.text,
        comments: _commentsCtrl.text,
        signatureBytes: _draft.signatureBytes,
        photos: List<Uint8List>.from(_draft.photos),
      ),
      onSaveDraft: _draft.saveAll,
      onDraftPersist: (reportId) async {
        _draft.pendingReportId = reportId;
        await _draft.saveAll();
      },
      onClearDraft: _draft.clear,
    );
    if (!mounted || result == null) return;
    if (result.pendingReportId != null) {
      setState(() => _draft.pendingReportId = result.pendingReportId);
    }
    if (result.shouldResetForm) {
      setState(_draft.resetAfterSubmit);
    }
  }

  Future<void> _openSignatureSheet() async {
    await showServiceReportSignatureSheet(
      context: context,
      onSave: (bytes) async {
        setState(() {
          _draft.signatureBytes = bytes;
          _draft.signatureSaved = true;
        });
        await _draft.saveAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).signatureSaved),
              backgroundColor: AppColors.success,
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(serviceReportControllerProvider).isLoading;
    final profile = ref.watch(profileProvider).valueOrNull;
    final canSubmit = ServiceReportWorkflow.canCreateOrUpdateReport(
      profile?.role,
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: ServiceReportAppBar(
        signatureSaved: _draft.signatureSaved,
        isLoading: isLoading,
        canSubmit: canSubmit,
        onOpenSignature: _openSignatureSheet,
        onSubmit: _submit,
      ),
      bottomNavigationBar: ServiceReportActionBar(
        signatureSaved: _draft.signatureSaved,
        isLoading: isLoading,
        canSubmit: canSubmit,
        onOpenSignature: _openSignatureSheet,
        onSubmit: _submit,
      ),
      body: ServiceReportFormBody(
        formKey: _formKey,
        canSubmit: canSubmit,
        showLinkedWorkOrderBanner: widget.initialWorkOrderId != null,
        selectedWorkOrderId: _draft.selectedWorkOrderId,
        complaintController: _complaintCtrl,
        causeController: _causeCtrl,
        correctionController: _correctionCtrl,
        collateralController: _collateralCtrl,
        commentsController: _commentsCtrl,
        photos: _draft.photos,
        onWorkOrderChanged: (value) {
          setState(() => _draft.selectedWorkOrderId = value);
          _draft.saveText();
        },
        onPickGallery: () =>
            _addPhoto(() => pickServiceReportGalleryPhoto(_picker)),
        onTakeCamera: () =>
            _addPhoto(() => takeServiceReportCameraPhoto(_picker)),
        onRemovePhoto: (index) {
          setState(() => _draft.photos.removeAt(index));
          _draft.saveAll();
        },
      ),
    );
  }
}
