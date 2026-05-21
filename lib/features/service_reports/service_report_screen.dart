import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_repository.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/features/service_reports/signature_pad_widget.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/work_order.dart';

class ServiceReportDraftCodec {
  const ServiceReportDraftCodec._();

  static bool hasTextDraft({
    required String? workOrderId,
    required String? pendingReportId,
    required String complaint,
    required String cause,
    required String correction,
    required String collateral,
    required String comments,
  }) {
    return workOrderId != null ||
        pendingReportId != null ||
        complaint.trim().isNotEmpty ||
        cause.trim().isNotEmpty ||
        correction.trim().isNotEmpty ||
        collateral.trim().isNotEmpty ||
        comments.trim().isNotEmpty;
  }

  static Map<String, dynamic> textPayload({
    required String? workOrderId,
    required String? pendingReportId,
    required String complaint,
    required String cause,
    required String correction,
    required String collateral,
    required String comments,
  }) {
    return {
      'workOrderId': workOrderId,
      'pendingReportId': pendingReportId,
      'complaint': complaint,
      'cause': cause,
      'correction': correction,
      'collateral': collateral,
      'comments': comments,
    };
  }

  static bool hasMediaDraft(Uint8List? signatureBytes, List<Uint8List> photos) {
    return signatureBytes != null || photos.isNotEmpty;
  }

  static Map<String, dynamic> mediaPayload(
    Uint8List? signatureBytes,
    List<Uint8List> photos,
  ) {
    return {
      'signatureBytes':
          signatureBytes == null ? null : base64Encode(signatureBytes),
      'photos': photos.map(base64Encode).toList(),
    };
  }
}

class ServiceReportScreen extends ConsumerStatefulWidget {
  final String? initialWorkOrderId;

  const ServiceReportScreen({super.key, this.initialWorkOrderId});

  @override
  ConsumerState<ServiceReportScreen> createState() =>
      _ServiceReportScreenState();
}

class _ServiceReportScreenState extends ConsumerState<ServiceReportScreen> {
  final _formKey = GlobalKey<FormState>();

  // 5-C fields
  final _complaintCtrl = TextEditingController();
  final _causeCtrl = TextEditingController();
  final _correctionCtrl = TextEditingController();
  final _collateralCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();

  String? _selectedWorkOrderId;
  String? _pendingReportId;
  Uint8List? _signatureBytes;
  bool _signatureSaved = false;
  bool _restoringDraft = false;
  final List<Uint8List> _photos = [];
  final ImagePicker _picker = ImagePicker();
  Timer? _draftSaveDebounce;

  String get _draftKey => widget.initialWorkOrderId?.isNotEmpty == true
      ? 'service_report_draft_${widget.initialWorkOrderId}'
      : 'service_report_draft';
  String get _draftMediaKey => '${_draftKey}_media';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _selectedWorkOrderId = widget.initialWorkOrderId;
      await _loadDraft();
      _complaintCtrl.addListener(_scheduleDraftTextSave);
      _causeCtrl.addListener(_scheduleDraftTextSave);
      _correctionCtrl.addListener(_scheduleDraftTextSave);
      _collateralCtrl.addListener(_scheduleDraftTextSave);
      _commentsCtrl.addListener(_scheduleDraftTextSave);
    });
  }

  @override
  void dispose() {
    _draftSaveDebounce?.cancel();
    _complaintCtrl.removeListener(_scheduleDraftTextSave);
    _causeCtrl.removeListener(_scheduleDraftTextSave);
    _correctionCtrl.removeListener(_scheduleDraftTextSave);
    _collateralCtrl.removeListener(_scheduleDraftTextSave);
    _commentsCtrl.removeListener(_scheduleDraftTextSave);
    _complaintCtrl.dispose();
    _causeCtrl.dispose();
    _correctionCtrl.dispose();
    _collateralCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  static const _submitFailedMessage =
      'Service report could not be submitted right now. Reconnect and try again.';
  static const _signatureFailedMessage =
      'Signature could not be uploaded right now. Reconnect and try again.';
  static const _photosPendingMessage =
      'Report saved, but photos are still on this device. Reopen and retry when connected.';

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    final mediaRaw = prefs.getString(_draftMediaKey);
    if (raw == null && mediaRaw == null) return;

    _restoringDraft = true;
    try {
      final data = raw == null
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map).cast<String, dynamic>();
      final mediaData = mediaRaw == null
          ? data
          : (jsonDecode(mediaRaw) as Map).cast<String, dynamic>();
      _selectedWorkOrderId = data['workOrderId'] as String?;
      _pendingReportId = data['pendingReportId'] as String?;
      _complaintCtrl.text = data['complaint'] as String? ?? '';
      _causeCtrl.text = data['cause'] as String? ?? '';
      _correctionCtrl.text = data['correction'] as String? ?? '';
      _collateralCtrl.text = data['collateral'] as String? ?? '';
      _commentsCtrl.text = data['comments'] as String? ?? '';

      final signature = mediaData['signatureBytes'];
      if (signature is String && signature.isNotEmpty) {
        _signatureBytes = base64Decode(signature);
        _signatureSaved = true;
      }

      _photos.clear();
      final photos = mediaData['photos'];
      if (photos is List) {
        for (final value in photos) {
          if (value is String && value.isNotEmpty) {
            _photos.add(base64Decode(value));
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      await prefs.remove(_draftKey);
      await prefs.remove(_draftMediaKey);
    } finally {
      _restoringDraft = false;
    }
  }

  void _scheduleDraftTextSave() {
    if (_restoringDraft) return;
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveDraftText());
    });
  }

  Future<void> _saveDraft() async {
    _draftSaveDebounce?.cancel();
    await _saveDraftText();
    await _saveDraftMedia();
  }

  Future<void> _saveDraftText() async {
    if (_restoringDraft) return;
    final prefs = await SharedPreferences.getInstance();
    final hasDraft = ServiceReportDraftCodec.hasTextDraft(
      workOrderId: _selectedWorkOrderId,
      pendingReportId: _pendingReportId,
      complaint: _complaintCtrl.text,
      cause: _causeCtrl.text,
      correction: _correctionCtrl.text,
      collateral: _collateralCtrl.text,
      comments: _commentsCtrl.text,
    );

    if (!hasDraft) {
      await prefs.remove(_draftKey);
      return;
    }

    await prefs.setString(
      _draftKey,
      jsonEncode(
        ServiceReportDraftCodec.textPayload(
          workOrderId: _selectedWorkOrderId,
          pendingReportId: _pendingReportId,
          complaint: _complaintCtrl.text,
          cause: _causeCtrl.text,
          correction: _correctionCtrl.text,
          collateral: _collateralCtrl.text,
          comments: _commentsCtrl.text,
        ),
      ),
    );
  }

  Future<void> _saveDraftMedia() async {
    if (_restoringDraft) return;
    final prefs = await SharedPreferences.getInstance();
    if (!ServiceReportDraftCodec.hasMediaDraft(_signatureBytes, _photos)) {
      await prefs.remove(_draftMediaKey);
      return;
    }

    await prefs.setString(
      _draftMediaKey,
      jsonEncode(ServiceReportDraftCodec.mediaPayload(
        _signatureBytes,
        _photos,
      )),
    );
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
    await prefs.remove(_draftMediaKey);
  }

  Future<String?> _uploadSignature() async {
    if (_signatureBytes == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '${_selectedWorkOrderId}_$ts.png';
    await supabase.storage
        .from(AppConstants.bucketSignatures)
        .uploadBinary(
          path,
          _signatureBytes!,
          fileOptions: const FileOptions(contentType: 'image/png'),
        )
        .timeout(const Duration(seconds: 4));
    return supabase.storage
        .from(AppConstants.bucketSignatures)
        .getPublicUrl(path);
  }

  Map<String, dynamic> _reportPayload(String? signatureUrl) => {
        'work_order_id': _selectedWorkOrderId?.isNotEmpty == true
            ? _selectedWorkOrderId
            : null,
        'complaint': _complaintCtrl.text.trim().isNotEmpty
            ? _complaintCtrl.text.trim()
            : null,
        'cause':
            _causeCtrl.text.trim().isNotEmpty ? _causeCtrl.text.trim() : null,
        'correction': _correctionCtrl.text.trim().isNotEmpty
            ? _correctionCtrl.text.trim()
            : null,
        'collateral': _collateralCtrl.text.trim().isNotEmpty
            ? _collateralCtrl.text.trim()
            : null,
        'comments': _commentsCtrl.text.trim().isNotEmpty
            ? _commentsCtrl.text.trim()
            : null,
        if (signatureUrl != null) ...{
          'tech_signature_url': signatureUrl,
          'signed_at': DateTime.now().toIso8601String(),
        },
      };

  Future<void> _updatePendingReport(
      String reportId, String? signatureUrl) async {
    await supabase
        .from(AppConstants.tServiceReports)
        .update(_reportPayload(signatureUrl))
        .eq('id', reportId)
        .timeout(const Duration(seconds: 4));
  }

  Future<void> _uploadPhotos(String serviceReportId) async {
    for (var i = 0; i < _photos.length; i++) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '$serviceReportId/${i}_$ts.jpg';
      await supabase.storage
          .from(AppConstants.bucketReportPhotos)
          .uploadBinary(
            path,
            _photos[i],
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          )
          .timeout(const Duration(seconds: 4));
      final photoUrl = supabase.storage
          .from(AppConstants.bucketReportPhotos)
          .getPublicUrl(path);
      await supabase.from(AppConstants.tServiceReportPhotos).insert({
        'service_report_id': serviceReportId,
        'photo_url': photoUrl,
        'sort_order': i,
      }).timeout(const Duration(seconds: 4));
    }
  }

  Future<void> _pickPhoto() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() => _photos.add(bytes));
      await _saveDraft();
    }
  }

  Future<void> _takePhoto() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() => _photos.add(bytes));
      await _saveDraft();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWorkOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a work order before submitting the report.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    await _saveDraft();

    // Upload signature to Supabase Storage. If a previous report was created
    // but photo upload failed, retry against that report instead of creating a
    // duplicate report. When retrying, update the saved report fields first so
    // field edits made after the partial failure are not silently dropped.
    String? signatureUrl;
    if (_signatureBytes != null) {
      try {
        signatureUrl = await _uploadSignature();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(_signatureFailedMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    if (_pendingReportId != null) {
      try {
        await _updatePendingReport(_pendingReportId!, signatureUrl);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(_submitFailedMessage),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    final selectedWorkOrderId = _selectedWorkOrderId;
    if (selectedWorkOrderId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).selectWorkOrder),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final submitResult = _pendingReportId == null
        ? await ref.read(serviceReportControllerProvider.notifier).createReport(
              workOrderId: selectedWorkOrderId,
              complaint: _complaintCtrl.text.trim().isNotEmpty
                  ? _complaintCtrl.text.trim()
                  : null,
              cause: _causeCtrl.text.trim().isNotEmpty
                  ? _causeCtrl.text.trim()
                  : null,
              correction: _correctionCtrl.text.trim().isNotEmpty
                  ? _correctionCtrl.text.trim()
                  : null,
              collateral: _collateralCtrl.text.trim().isNotEmpty
                  ? _collateralCtrl.text.trim()
                  : null,
              comments: _commentsCtrl.text.trim().isNotEmpty
                  ? _commentsCtrl.text.trim()
                  : null,
              techSignatureUrl: signatureUrl,
            )
        : ServiceReportSubmitResult(reportId: _pendingReportId!, synced: true);
    final reportId = submitResult?.reportId;

    if (reportId != null) {
      _pendingReportId = reportId;
      await _saveDraft();
      var photosUploaded = true;
      if (_photos.isNotEmpty) {
        try {
          await _uploadPhotos(reportId);
        } catch (_) {
          photosUploaded = false;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(photosUploaded
              ? AppLocalizations.of(context).reportSubmitted
              : _photosPendingMessage),
          backgroundColor:
              photosUploaded ? AppColors.success : AppColors.warning,
        ),
      );
      if (photosUploaded) {
        _formKey.currentState!.reset();
        setState(() {
          _selectedWorkOrderId = null;
          _pendingReportId = null;
          _signatureBytes = null;
          _signatureSaved = false;
          _photos.clear();
        });
        await _clearDraft();
        if (mounted) context.pop();
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(_submitFailedMessage),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _sectionHeader(BuildContext context, String title,
      {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.primary, letterSpacing: 0.8),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reportTextField({
    required TextEditingController controller,
    required String hintText,
    bool requiredField = false,
    int minLines = 2,
    int maxLines = 3,
  }) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      scrollPadding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hintText,
        alignLabelWithHint: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: requiredField
          ? (v) => (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null
          : null,
    );
  }

  Future<void> _openSignatureSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    AppLocalizations.of(sheetContext).technicianSignature,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SignaturePadWidget(
                onSave: (bytes) async {
                  setState(() {
                    _signatureBytes = bytes;
                    _signatureSaved = true;
                  });
                  await _saveDraft();
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(AppLocalizations.of(context).signatureSaved),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(serviceReportControllerProvider).isLoading;
    final profile = ref.watch(profileProvider).valueOrNull;
    final canSubmit =
        ServiceReportWorkflow.canCreateOrUpdateReport(profile?.role);
    final workOrdersAsync = ref.watch(workOrdersProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(l10n.serviceReportTitle),
        actions: [
          Tooltip(
            message: _signatureSaved
                ? l10n.signatureCaptured
                : l10n.technicianSignature,
            child: IconButton(
              onPressed: _openSignatureSheet,
              icon: Icon(
                _signatureSaved ? Icons.check_circle : Icons.draw_outlined,
                color: _signatureSaved ? AppColors.success : null,
              ),
            ),
          ),
          Tooltip(
            message: l10n.submitReport,
            child: IconButton(
              onPressed: isLoading || !canSubmit
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      _submit();
                    },
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 104),
              children: [
                if (!canSubmit) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'Only owner and employee accounts can submit service reports.',
                      style: TextStyle(color: AppColors.warning),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.initialWorkOrderId != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Linked to this work order. Fill the 5C fields below.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _sectionHeader(context, l10n.linkedWorkOrder),
                workOrdersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, __) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Could not load work orders: $error',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                  data: (orders) {
                    final active = orders
                        .where((w) =>
                            ServiceReportWorkflow.canAttachReportToWorkOrder(
                                w.status))
                        .toList();
                    final hasSelectedWorkOrder = active.any(
                      (w) => w.id == _selectedWorkOrderId,
                    );
                    if (active.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'No cached work orders are available. Reopen from a work order or reconnect and try again.',
                          style: TextStyle(color: AppColors.warning),
                        ),
                      );
                    }
                    Widget workOrderLabel(WorkOrder w) => Text(
                          w.status == WorkOrderStatus.closed
                              ? '${w.title} • closed'
                              : w.title,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        );

                    return DropdownButtonFormField<String>(
                      initialValue:
                          hasSelectedWorkOrder ? _selectedWorkOrderId : null,
                      isExpanded: true,
                      selectedItemBuilder: (context) => active
                          .map(
                            (w) => Align(
                              alignment: Alignment.centerLeft,
                              child: workOrderLabel(w),
                            ),
                          )
                          .toList(),
                      decoration: InputDecoration(
                        labelText: l10n.linkedWorkOrder,
                        prefixIcon: const Icon(Icons.build_outlined),
                      ),
                      dropdownColor: AppColors.surfaceVariant,
                      items: active
                          .map(
                            (w) => DropdownMenuItem(
                              value: w.id,
                              child: workOrderLabel(w),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() => _selectedWorkOrderId = v);
                        _saveDraftText();
                      },
                    );
                  },
                ),
                _sectionHeader(
                  context,
                  l10n.srComplaint,
                  subtitle: l10n.srComplaintSub,
                ),
                _reportTextField(
                  controller: _complaintCtrl,
                  hintText: l10n.srComplaintHint,
                  requiredField: true,
                ),
                _sectionHeader(
                  context,
                  l10n.srCause,
                  subtitle: l10n.srCauseSub,
                ),
                _reportTextField(
                  controller: _causeCtrl,
                  hintText: l10n.srCauseHint,
                  requiredField: true,
                ),
                _sectionHeader(
                  context,
                  l10n.srCorrection,
                  subtitle: l10n.srCorrectionSub,
                ),
                _reportTextField(
                  controller: _correctionCtrl,
                  hintText: l10n.srCorrectionHint,
                  requiredField: true,
                  maxLines: 4,
                ),
                _sectionHeader(
                  context,
                  l10n.srSecondaryDamage,
                  subtitle: l10n.srSecondaryDamageSub,
                ),
                _reportTextField(
                  controller: _collateralCtrl,
                  hintText: l10n.srSecondaryDamageHint,
                ),
                _sectionHeader(
                  context,
                  l10n.srComments,
                  subtitle: l10n.srCommentsSub,
                ),
                _reportTextField(
                  controller: _commentsCtrl,
                  hintText: l10n.srCommentsHint,
                ),
                _sectionHeader(
                  context,
                  l10n.serviceReportPhotos,
                  subtitle: l10n.serviceReportPhotosHint,
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('Gallery'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: const Text('Camera'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_photos.isNotEmpty) ...[
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _photos[i],
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _photos.removeAt(i));
                                  _saveDraft();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
