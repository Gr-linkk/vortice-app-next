import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_provider.dart';
import 'package:vortice_app/features/service_reports/service_report_workflow.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';
import 'package:vortice_app/models/profile.dart';

class ServiceReportAuthoringScreenV2 extends ConsumerStatefulWidget {
  const ServiceReportAuthoringScreenV2({
    super.key,
    required this.workOrderId,
  });

  final String? workOrderId;

  @override
  ConsumerState<ServiceReportAuthoringScreenV2> createState() =>
      _ServiceReportAuthoringScreenV2State();
}

class _ServiceReportAuthoringScreenV2State
    extends ConsumerState<ServiceReportAuthoringScreenV2> {
  final _formKey = GlobalKey<FormState>();
  final _complaintCtrl = TextEditingController();
  final _causeCtrl = TextEditingController();
  final _correctionCtrl = TextEditingController();
  final _collateralCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();

  Timer? _saveDebounce;
  bool _loadingDraft = true;
  bool _savingDraft = false;
  bool _draftRestored = false;

  String get _draftKey => 'service_report_v2_draft_${widget.workOrderId}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadDraft();
      _complaintCtrl.addListener(_scheduleDraftSave);
      _causeCtrl.addListener(_scheduleDraftSave);
      _correctionCtrl.addListener(_scheduleDraftSave);
      _collateralCtrl.addListener(_scheduleDraftSave);
      _commentsCtrl.addListener(_scheduleDraftSave);
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _complaintCtrl.removeListener(_scheduleDraftSave);
    _causeCtrl.removeListener(_scheduleDraftSave);
    _correctionCtrl.removeListener(_scheduleDraftSave);
    _collateralCtrl.removeListener(_scheduleDraftSave);
    _commentsCtrl.removeListener(_scheduleDraftSave);
    _complaintCtrl.dispose();
    _causeCtrl.dispose();
    _correctionCtrl.dispose();
    _collateralCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    if (widget.workOrderId == null || widget.workOrderId!.isEmpty) {
      if (mounted) setState(() => _loadingDraft = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw != null) {
      try {
        final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
        _complaintCtrl.text = data['complaint'] as String? ?? '';
        _causeCtrl.text = data['cause'] as String? ?? '';
        _correctionCtrl.text = data['correction'] as String? ?? '';
        _collateralCtrl.text = data['collateral'] as String? ?? '';
        _commentsCtrl.text = data['comments'] as String? ?? '';
        _draftRestored = true;
      } catch (_) {
        await prefs.remove(_draftKey);
      }
    }

    if (mounted) setState(() => _loadingDraft = false);
  }

  void _scheduleDraftSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveDraft(showMessage: false));
    });
  }

  bool get _hasDraftText =>
      _complaintCtrl.text.trim().isNotEmpty ||
      _causeCtrl.text.trim().isNotEmpty ||
      _correctionCtrl.text.trim().isNotEmpty ||
      _collateralCtrl.text.trim().isNotEmpty ||
      _commentsCtrl.text.trim().isNotEmpty;

  Future<void> _saveDraft({required bool showMessage}) async {
    if (widget.workOrderId == null || widget.workOrderId!.isEmpty) return;
    _saveDebounce?.cancel();
    if (mounted) setState(() => _savingDraft = true);

    final prefs = await SharedPreferences.getInstance();
    if (_hasDraftText) {
      await prefs.setString(
        _draftKey,
        jsonEncode({
          'workOrderId': widget.workOrderId,
          'complaint': _complaintCtrl.text,
          'cause': _causeCtrl.text,
          'correction': _correctionCtrl.text,
          'collateral': _collateralCtrl.text,
          'comments': _commentsCtrl.text,
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );
    } else {
      await prefs.remove(_draftKey);
    }

    if (!mounted) return;
    setState(() => _savingDraft = false);
    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft saved on this device')),
      );
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  Future<void> _submit() async {
    if (widget.workOrderId == null || widget.workOrderId!.isEmpty) return;
    if (!_formKey.currentState!.validate()) return;

    await _saveDraft(showMessage: false);

    final result = await ref
        .read(serviceReportControllerProvider.notifier)
        .createReport(
          workOrderId: widget.workOrderId!,
          complaint: _complaintCtrl.text.trim(),
          cause: _causeCtrl.text.trim(),
          correction: _correctionCtrl.text.trim(),
          collateral: _collateralCtrl.text.trim().isEmpty
              ? null
              : _collateralCtrl.text.trim(),
          comments: _commentsCtrl.text.trim().isEmpty
              ? null
              : _commentsCtrl.text.trim(),
        );

    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service report could not be submitted.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    await _clearDraft();
    if (!mounted) return;

    final profile = ref.read(profileProvider).valueOrNull;
    final prefix = _routePrefix(profile?.role);
    final encodedWorkOrderId = Uri.encodeComponent(widget.workOrderId!);
    final message = result.synced
        ? 'Service report submitted'
        : 'Report saved locally. Sync pending.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: result.synced ? AppColors.success : AppColors.warning,
      ),
    );
    context.go('$prefix/service-reports?workOrderId=$encodedWorkOrderId');
  }

  @override
  Widget build(BuildContext context) {
    final workOrderId = widget.workOrderId;
    final profileAsync = ref.watch(profileProvider);
    if (profileAsync.isLoading) {
      return const Scaffold(
        appBar: _ServiceReportV2AppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (profileAsync.hasError) {
      return Scaffold(
        appBar: const _ServiceReportV2AppBar(),
        body: _BlockingMessage(
          icon: Icons.error_outline,
          title: 'Could not load profile',
          message: profileAsync.error.toString(),
        ),
      );
    }

    final profile = profileAsync.valueOrNull;
    final canAuthor = ServiceReportWorkflow.canCreateOrUpdateReport(
      profile?.role,
    );
    final submitting = ref.watch(serviceReportControllerProvider).isLoading;

    if (workOrderId == null || workOrderId.isEmpty) {
      return const Scaffold(
        appBar: _ServiceReportV2AppBar(),
        body: _BlockingMessage(
          icon: Icons.link_off,
          title: 'No work order selected',
          message: 'Open this from a work order to create a service report.',
        ),
      );
    }

    if (!canAuthor) {
      return const Scaffold(
        appBar: _ServiceReportV2AppBar(),
        body: _BlockingMessage(
          icon: Icons.lock_outline,
          title: 'Service report unavailable',
          message: 'Only Vortice staff can create service reports.',
        ),
      );
    }

    final workOrderAsync = ref.watch(workOrderByIdProvider(workOrderId));

    return Scaffold(
      appBar: const _ServiceReportV2AppBar(),
      body: workOrderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _BlockingMessage(
          icon: Icons.error_outline,
          title: 'Could not load work order',
          message: error.toString(),
        ),
        data: (workOrder) {
          if (workOrder == null) {
            return const _BlockingMessage(
              icon: Icons.search_off,
              title: 'Work order not found',
              message: 'Go back to the work order list and try again.',
            );
          }

          return Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                Text(
                  workOrder.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Work order ${workOrder.id}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (_loadingDraft) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ] else if (_draftRestored) ...[
                  const SizedBox(height: 16),
                  const _InlineNotice(
                    icon: Icons.restore,
                    text: 'Draft restored from this device',
                  ),
                ],
                const SizedBox(height: 20),
                _ServiceReportTextField(
                  controller: _complaintCtrl,
                  label: 'Complaint',
                  requiredField: true,
                  minLines: 3,
                ),
                const SizedBox(height: 12),
                _ServiceReportTextField(
                  controller: _causeCtrl,
                  label: 'Cause',
                  requiredField: true,
                  minLines: 3,
                ),
                const SizedBox(height: 12),
                _ServiceReportTextField(
                  controller: _correctionCtrl,
                  label: 'Correction',
                  requiredField: true,
                  minLines: 3,
                ),
                const SizedBox(height: 12),
                _ServiceReportTextField(
                  controller: _collateralCtrl,
                  label: 'Collateral',
                  minLines: 2,
                ),
                const SizedBox(height: 12),
                _ServiceReportTextField(
                  controller: _commentsCtrl,
                  label: 'Comments',
                  minLines: 3,
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: submitting || _savingDraft || _loadingDraft
                      ? null
                      : () => _saveDraft(showMessage: true),
                  icon: _savingDraft
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: submitting || _loadingDraft
                      ? null
                      : () => unawaited(_submit()),
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _routePrefix(UserRole? role) => switch (role) {
      UserRole.employee => '/employee',
      _ => '/owner',
    };

class _ServiceReportV2AppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _ServiceReportV2AppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('New Service Report'));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ServiceReportTextField extends StatelessWidget {
  const _ServiceReportTextField({
    required this.controller,
    required this.label,
    this.requiredField = false,
    this.minLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool requiredField;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: null,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        labelText: requiredField ? '$label *' : label,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
      validator: requiredField
          ? (value) => value == null || value.trim().isEmpty
              ? '$label is required'
              : null
          : null,
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockingMessage extends StatelessWidget {
  const _BlockingMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
