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
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/signature_pad_widget.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/work_order.dart';

class ServiceReportScreen extends ConsumerStatefulWidget {
  const ServiceReportScreen({super.key});

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

  String get _draftKey => 'service_report_draft';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDraft();
      _complaintCtrl.addListener(_saveDraft);
      _causeCtrl.addListener(_saveDraft);
      _correctionCtrl.addListener(_saveDraft);
      _collateralCtrl.addListener(_saveDraft);
      _commentsCtrl.addListener(_saveDraft);
    });
  }

  @override
  void dispose() {
    _complaintCtrl.removeListener(_saveDraft);
    _causeCtrl.removeListener(_saveDraft);
    _correctionCtrl.removeListener(_saveDraft);
    _collateralCtrl.removeListener(_saveDraft);
    _commentsCtrl.removeListener(_saveDraft);
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
    if (raw == null) return;

    _restoringDraft = true;
    try {
      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _selectedWorkOrderId = data['workOrderId'] as String?;
      _pendingReportId = data['pendingReportId'] as String?;
      _complaintCtrl.text = data['complaint'] as String? ?? '';
      _causeCtrl.text = data['cause'] as String? ?? '';
      _correctionCtrl.text = data['correction'] as String? ?? '';
      _collateralCtrl.text = data['collateral'] as String? ?? '';
      _commentsCtrl.text = data['comments'] as String? ?? '';

      final signature = data['signatureBytes'];
      if (signature is String && signature.isNotEmpty) {
        _signatureBytes = base64Decode(signature);
        _signatureSaved = true;
      }

      _photos.clear();
      final photos = data['photos'];
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
    } finally {
      _restoringDraft = false;
    }
  }

  Future<void> _saveDraft() async {
    if (_restoringDraft) return;
    final prefs = await SharedPreferences.getInstance();
    final hasDraft = _selectedWorkOrderId != null ||
        _pendingReportId != null ||
        _complaintCtrl.text.trim().isNotEmpty ||
        _causeCtrl.text.trim().isNotEmpty ||
        _correctionCtrl.text.trim().isNotEmpty ||
        _collateralCtrl.text.trim().isNotEmpty ||
        _commentsCtrl.text.trim().isNotEmpty ||
        _signatureBytes != null ||
        _photos.isNotEmpty;

    if (!hasDraft) {
      await prefs.remove(_draftKey);
      return;
    }

    await prefs.setString(
      _draftKey,
      jsonEncode({
        'workOrderId': _selectedWorkOrderId,
        'pendingReportId': _pendingReportId,
        'complaint': _complaintCtrl.text,
        'cause': _causeCtrl.text,
        'correction': _correctionCtrl.text,
        'collateral': _collateralCtrl.text,
        'comments': _commentsCtrl.text,
        'signatureBytes':
            _signatureBytes == null ? null : base64Encode(_signatureBytes!),
        'photos': _photos.map(base64Encode).toList(),
      }),
    );
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
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
    // WO is optional when opened standalone — warn but don't block
    if (_selectedWorkOrderId == null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No Work Order Selected'),
          content: const Text(
              'Submit without linking to a work order? You can add it later from the report detail.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit Anyway')),
          ],
        ),
      );
      if (proceed != true) return;
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

    final reportId = _pendingReportId ??
        await ref.read(serviceReportControllerProvider.notifier).createReport(
              workOrderId: _selectedWorkOrderId,
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
            );

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
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.primary, letterSpacing: 1.2),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(serviceReportControllerProvider).isLoading;
    final workOrdersAsync = ref.watch(workOrdersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.serviceReportTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Work order selector ─────────────────────────────────
              _sectionHeader(context, l10n.linkedWorkOrder),
              workOrdersAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
                data: (orders) {
                  final active = orders
                      .where((w) =>
                          w.status == WorkOrderStatus.inProgress ||
                          w.status == WorkOrderStatus.draft ||
                          w.status == WorkOrderStatus.assigned)
                      .toList();
                  final hasSelectedWorkOrder = active.any(
                    (w) => w.id == _selectedWorkOrderId,
                  );
                  return DropdownButtonFormField<String>(
                    initialValue:
                        hasSelectedWorkOrder ? _selectedWorkOrderId : null,
                    decoration: InputDecoration(
                      labelText: l10n.linkedWorkOrder,
                      prefixIcon: const Icon(Icons.build_outlined),
                    ),
                    dropdownColor: AppColors.surfaceVariant,
                    items: active
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.title,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedWorkOrderId = v);
                      _saveDraft();
                    },
                  );
                },
              ),

              // ── 5-C Fields ──────────────────────────────────────────

              _sectionHeader(
                context,
                l10n.srComplaint,
                subtitle: l10n.srComplaintSub,
              ),
              TextFormField(
                controller: _complaintCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.srComplaintHint,
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),

              _sectionHeader(
                context,
                l10n.srCause,
                subtitle: l10n.srCauseSub,
              ),
              TextFormField(
                controller: _causeCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.srCauseHint,
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),

              _sectionHeader(
                context,
                l10n.srCorrection,
                subtitle: l10n.srCorrectionSub,
              ),
              TextFormField(
                controller: _correctionCtrl,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.srCorrectionHint,
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),

              _sectionHeader(
                context,
                l10n.srSecondaryDamage,
                subtitle: l10n.srSecondaryDamageSub,
              ),
              TextFormField(
                controller: _collateralCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.srSecondaryDamageHint,
                  alignLabelWithHint: true,
                ),
              ),

              _sectionHeader(
                context,
                l10n.srComments,
                subtitle: l10n.srCommentsSub,
              ),
              TextFormField(
                controller: _commentsCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.srCommentsHint,
                  alignLabelWithHint: true,
                ),
              ),

              // ── Photos ─────────────────────────────────────────────
              _sectionHeader(
                context,
                l10n.serviceReportPhotos,
                subtitle: l10n.serviceReportPhotosHint,
              ),
              // Add photo buttons — always visible
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
              // ── Signature ───────────────────────────────────────────
              _sectionHeader(context, l10n.technicianSignature),
              SignaturePadWidget(
                onSave: (bytes) async {
                  setState(() {
                    _signatureBytes = bytes;
                    _signatureSaved = true;
                  });
                  await _saveDraft();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.signatureSaved),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
              ),
              if (_signatureSaved) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppColors.success, size: 16),
                    const SizedBox(width: 6),
                    Text(l10n.signatureCaptured,
                        style: const TextStyle(
                            color: AppColors.success, fontSize: 13)),
                  ],
                ),
              ],

              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: isLoading ? null : _submit,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: Text(l10n.submitReport),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
