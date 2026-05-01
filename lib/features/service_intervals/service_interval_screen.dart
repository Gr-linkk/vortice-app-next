import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/checklists/checklist_provider.dart';
import 'package:vortice_app/features/service_intervals/service_interval_provider.dart';
import 'package:vortice_app/features/subscription/tier_gate.dart';
import 'package:vortice_app/features/subscription/upgrade_prompt.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/asset_service_interval.dart';
import 'package:vortice_app/models/checklist_template.dart';
import 'package:vortice_app/models/subscription_tier.dart';

class ServiceIntervalScreen extends ConsumerStatefulWidget {
  const ServiceIntervalScreen({super.key});

  @override
  ConsumerState<ServiceIntervalScreen> createState() =>
      _ServiceIntervalScreenState();
}

class _ServiceIntervalScreenState
    extends ConsumerState<ServiceIntervalScreen> {
  Asset? _selectedAsset;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    if (!hasTier(profile, SubscriptionTier.planning)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Service Intervals')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: UpgradePrompt(requiredTier: SubscriptionTier.planning),
          ),
        ),
      );
    }

    final assetsAsync = ref.watch(assetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Service Intervals')),
      floatingActionButton: _selectedAsset == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddSheet(context, _selectedAsset!.id),
              icon: const Icon(Icons.add),
              label: const Text('Add Interval'),
              backgroundColor: AppColors.primary,
            ),
      body: Column(
        children: [
          // ── Asset picker ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: assetsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text(err.toString(),
                  style: const TextStyle(color: AppColors.error)),
              data: (assets) => DropdownButtonFormField<Asset>(
                value: _selectedAsset,
                decoration: const InputDecoration(
                  labelText: 'Select Asset',
                  prefixIcon: Icon(Icons.directions_boat_outlined),
                ),
                dropdownColor: AppColors.surfaceVariant,
                items: assets
                    .map((a) => DropdownMenuItem<Asset>(
                          value: a,
                          child: Text(a.name,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (a) => setState(() => _selectedAsset = a),
              ),
            ),
          ),

          // ── Interval list ──────────────────────────────────────────
          Expanded(
            child: _selectedAsset == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule,
                            size: 56,
                            color: AppColors.textSecondary),
                        SizedBox(height: 12),
                        Text(
                          'Select an asset to manage its\nservice intervals.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : _IntervalList(assetId: _selectedAsset!.id),
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context, String assetId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddIntervalSheet(assetId: assetId),
    );
  }
}

// ── Interval List ─────────────────────────────────────────────────────────────

class _IntervalList extends ConsumerWidget {
  final String assetId;
  const _IntervalList({required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intervalsAsync = ref.watch(serviceIntervalsProvider(assetId));

    return intervalsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(err.toString(),
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (intervals) {
        if (intervals.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 48, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text(
                  'No service intervals configured.\nTap + to add one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: intervals.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _IntervalCard(
            interval: intervals[i],
            assetId: assetId,
          ),
        );
      },
    );
  }
}

// ── Interval Card with swipe-to-delete ───────────────────────────────────────

class _IntervalCard extends ConsumerWidget {
  final AssetServiceInterval interval;
  final String assetId;
  const _IntervalCard({required this.interval, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(serviceIntervalControllerProvider).isLoading;

    return Dismissible(
      key: Key(interval.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Interval'),
            content: Text(
                'Delete the ${interval.intervalHours.toInt()}h service interval?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref
            .read(serviceIntervalControllerProvider.notifier)
            .deleteInterval(interval.id, assetId);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: interval.enabled
                ? AppColors.cardBorder
                : AppColors.cardBorder.withOpacity(0.4),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${interval.intervalHours.toInt()}h',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    interval.label ??
                        '${interval.intervalHours.toInt()}h Service',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: interval.enabled
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _TemplateLabel(
                      templateId: interval.checklistTemplateId),
                ],
              ),
            ),
            Switch(
              value: interval.enabled,
              activeColor: AppColors.primary,
              onChanged: isLoading
                  ? null
                  : (val) => ref
                      .read(serviceIntervalControllerProvider.notifier)
                      .updateInterval(
                        interval.id,
                        assetId: assetId,
                        enabled: val,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateLabel extends ConsumerWidget {
  final String? templateId;
  const _TemplateLabel({required this.templateId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (templateId == null) {
      return const Text(
        'No checklist template',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }
    final templatesAsync = ref.watch(checklistTemplatesProvider);
    return templatesAsync.when(
      loading: () => const Text('...',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      error: (_, __) => const Text('—',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      data: (templates) {
        final template = templates
            .where((t) => t.id == templateId)
            .firstOrNull;
        return Text(
          template?.name ?? 'Unknown template',
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12),
        );
      },
    );
  }
}

// ── Add Interval Sheet ────────────────────────────────────────────────────────

class _AddIntervalSheet extends ConsumerStatefulWidget {
  final String assetId;
  const _AddIntervalSheet({required this.assetId});

  @override
  ConsumerState<_AddIntervalSheet> createState() => _AddIntervalSheetState();
}

class _AddIntervalSheetState extends ConsumerState<_AddIntervalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _hoursCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  ChecklistTemplate? _selectedTemplate;

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final hours = double.tryParse(_hoursCtrl.text.trim());
    if (hours == null) return;

    final success = await ref
        .read(serviceIntervalControllerProvider.notifier)
        .createInterval(
          assetId: widget.assetId,
          intervalHours: hours,
          checklistTemplateId: _selectedTemplate?.id,
          label: _labelCtrl.text.trim().isNotEmpty
              ? _labelCtrl.text.trim()
              : null,
        );

    if (success && mounted) {
      Navigator.pop(context);
    } else if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save interval. Try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(serviceIntervalControllerProvider).isLoading;
    final templatesAsync = ref.watch(checklistTemplatesProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add Service Interval',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hoursCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Interval Hours (e.g. 250)',
                prefixIcon: Icon(Icons.schedule),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Required';
                }
                if (double.tryParse(v.trim()) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                prefixIcon: Icon(Icons.label_outline),
                hintText: 'e.g. 250h Oil Change',
              ),
            ),
            const SizedBox(height: 12),
            templatesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (templates) => DropdownButtonFormField<ChecklistTemplate?>(
                value: _selectedTemplate,
                decoration: const InputDecoration(
                  labelText: 'Checklist Template (optional)',
                  prefixIcon: Icon(Icons.checklist_outlined),
                ),
                dropdownColor: AppColors.surfaceVariant,
                items: [
                  const DropdownMenuItem<ChecklistTemplate?>(
                    value: null,
                    child: Text('— No template —',
                        style:
                            TextStyle(color: AppColors.textSecondary)),
                  ),
                  ...templates.map((t) => DropdownMenuItem<ChecklistTemplate?>(
                        value: t,
                        child: Text(t.name,
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (t) => setState(() => _selectedTemplate = t),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isLoading ? null : _save,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
