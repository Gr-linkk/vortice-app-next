import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/checklists/checklist_assignment_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';

class OrgAdminAssignChecklistSheet extends ConsumerStatefulWidget {
  final String orgId;
  final String assignedBy;

  const OrgAdminAssignChecklistSheet({
    super.key,
    required this.orgId,
    required this.assignedBy,
  });

  @override
  ConsumerState<OrgAdminAssignChecklistSheet> createState() =>
      _OrgAdminAssignChecklistSheetState();
}

class _OrgAdminAssignChecklistSheetState
    extends ConsumerState<OrgAdminAssignChecklistSheet> {
  String? _selectedTemplateId;
  String? _selectedMemberId;
  String? _selectedAssetId;
  bool _submitting = false;
  String _checklistType = 'pm'; // pm or operator_daily

  @override
  Widget build(BuildContext context) {
    final pmAsync = ref.watch(pmChecklistTemplatesProvider);
    final preOpAsync = ref.watch(preOpChecklistTemplatesProvider);
    final membersAsync = ref.watch(orgMembersProvider(widget.orgId));
    final assetsAsync = ref.watch(operatorScopedAssetsProvider);

    final templates = _checklistType == 'pm' ? pmAsync : preOpAsync;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Assign Checklist',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pm', label: Text('PM Checklist')),
              ButtonSegment(value: 'operator_daily', label: Text('Pre-Op')),
            ],
            selected: {_checklistType},
            onSelectionChanged: (v) => setState(() {
              _checklistType = v.first;
              _selectedTemplateId = null;
              _selectedMemberId = null;
            }),
          ),
          const SizedBox(height: 16),

          templates.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: _selectedTemplateId,
              decoration:
                  const InputDecoration(labelText: 'Checklist template'),
              dropdownColor: AppColors.surfaceVariant,
              items: list
                  .map((t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(
                          t['name'] as String? ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedTemplateId = v),
            ),
          ),
          const SizedBox(height: 12),

          membersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (members) {
              final filtered =
                  filterMembersForChecklistType(members, _checklistType);
              return DropdownButtonFormField<String>(
                initialValue: _selectedMemberId,
                decoration: InputDecoration(
                    labelText: _checklistType == 'pm'
                        ? 'Assign to mechanic'
                        : 'Assign to operator'),
                dropdownColor: AppColors.surfaceVariant,
                items: filtered
                    .map((m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.fullName),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedMemberId = v),
              );
            },
          ),
          const SizedBox(height: 12),

          assetsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (assets) => DropdownButtonFormField<String>(
              initialValue: _selectedAssetId,
              decoration: const InputDecoration(labelText: 'Vessel (optional)'),
              dropdownColor: AppColors.surfaceVariant,
              items: [
                const DropdownMenuItem(value: null, child: Text('No vessel')),
                ...assets.map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(a.name),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedAssetId = v),
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _submitting ||
                    _selectedTemplateId == null ||
                    _selectedMemberId == null
                ? null
                : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Assign'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ChecklistAssignmentController.assign(
        templateId: _selectedTemplateId!,
        assignedTo: _selectedMemberId!,
        assignedBy: widget.assignedBy,
        orgId: widget.orgId,
        assetId: _selectedAssetId,
      );
      ref.invalidate(orgChecklistAssignmentsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
