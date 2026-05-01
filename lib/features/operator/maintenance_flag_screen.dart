import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/notification_service.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/assets/asset_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/operator/operator_runs_provider.dart';
import 'package:vortice_app/models/asset.dart';

class MaintenanceFlagScreen extends ConsumerStatefulWidget {
  const MaintenanceFlagScreen({super.key});

  @override
  ConsumerState<MaintenanceFlagScreen> createState() =>
      _MaintenanceFlagScreenState();
}

class _MaintenanceFlagScreenState
    extends ConsumerState<MaintenanceFlagScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  String? _selectedAssetId;
  String _severity = 'normal';
  bool _submitting = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAssetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).selectAsset),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final profile = ref.read(profileProvider).valueOrNull;
      final assets = ref.read(operatorScopedAssetsProvider).valueOrNull ?? [];
      final asset = assets.firstWhere((a) => a.id == _selectedAssetId);

      final description = _descCtrl.text.trim();

      await supabase.from(AppConstants.tMaintenanceRequests).insert({
        'asset_id': _selectedAssetId,
        'client_id': asset.clientId,
        'flagged_by': profile?.id,
        'description': description,
        'severity': _severity,
        'status': 'open',
      });

      // Invalidate providers so dashboards refresh immediately
      ref.invalidate(openMaintenanceRequestsProvider);
      ref.invalidate(clientFlaggedIssuesProvider);

      // Insert in-app notification for the client
      await supabase.from(AppConstants.tNotifications).insert({
        'user_id': asset.clientId,
        'title': 'Equipment Issue Flagged: ${asset.name}',
        'body': description,
        'type': 'maintenance_flag',
        'reference_id': _selectedAssetId,
        'read': false,
      });

      // Send push notification to client (stub — replace with FCM when configured)
      await NotificationService.notifyClientOfMaintenanceFlag(
        clientId: asset.clientId,
        assetName: asset.name,
        issueDescription: description,
        severity: _severity,
      );

      // Also notify owner
      await NotificationService.notifyOwnerOfMaintenanceFlag(
        assetName: asset.name,
        operatorName: profile?.fullName ?? 'Operator',
        issueDescription: description,
        severity: _severity,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).flagSubmitted),
            backgroundColor: AppColors.success,
          ),
        );
        _formKey.currentState!.reset();
        _descCtrl.clear();
        setState(() {
          _selectedAssetId = null;
          _severity = 'normal';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final assetsAsync = (profile?.role == UserRole.operator ||
            profile?.role == UserRole.clientOperator ||
            profile?.role == UserRole.clientMechanic)
        ? ref.watch(operatorScopedAssetsProvider)
        : ref.watch(assetsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.maintenanceFlagTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Alert banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.flagInfo,
                        style: const TextStyle(
                            color: AppColors.warning, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              assetsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text(e.toString(),
                    style: const TextStyle(color: AppColors.error)),
                data: (assets) => DropdownButtonFormField<String>(
                  value: _selectedAssetId,
                  decoration: InputDecoration(
                    labelText: l10n.selectAsset,
                    prefixIcon: const Icon(Icons.directions_boat_outlined),
                  ),
                  dropdownColor: AppColors.surfaceVariant,
                  items: assets
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedAssetId = v),
                  validator: (v) =>
                      v == null ? l10n.fieldRequired : null,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.issueDescription,
                  alignLabelWithHint: true,
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 80),
                    child: Icon(Icons.description_outlined),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 16),
              Text(
                'SEVERITY',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.textSecondary, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _SeverityButton(
                    label: 'Normal',
                    value: 'normal',
                    selected: _severity == 'normal',
                    color: AppColors.warning,
                    onTap: () => setState(() => _severity = 'normal'),
                  ),
                  const SizedBox(width: 8),
                  _SeverityButton(
                    label: 'Urgent',
                    value: 'urgent',
                    selected: _severity == 'urgent',
                    color: AppColors.error,
                    onTap: () => setState(() => _severity = 'urgent'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.flag),
                label: Text(l10n.submitFlag),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeverityButton extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SeverityButton({
    required this.label,
    required this.value,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.2) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
