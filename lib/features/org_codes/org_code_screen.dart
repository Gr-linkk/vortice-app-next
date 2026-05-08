import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/org_codes/org_code_provider.dart';
import 'package:intl/intl.dart';

class OrgCodeScreen extends ConsumerWidget {
  const OrgCodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final codesAsync = ref.watch(orgCodesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.orgCodesTitle)),
      body: codesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(err.toString()),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(orgCodesProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (codes) {
          if (codes.isEmpty) {
            return Center(
              child: Text(l10n.noOrgCodes,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orgCodesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: codes.length,
              itemBuilder: (_, i) => _OrgCodeTile(
                code: codes[i],
                onDelete: () => _confirmDelete(context, ref, l10n, codes[i]),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSheet(context, ref, l10n),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, OrgCode code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(l10n.confirmDelete),
        content: Text(l10n.confirmDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => ctx.pop(true),
            child: Text(l10n.delete,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(orgCodeControllerProvider.notifier).deleteCode(code.id);
    }
  }

  void _showCreateSheet(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _OrgCodeForm(),
    );
  }
}

Color _roleColor(String role) => switch (role) {
      'owner' => AppColors.success,
      'employee' => AppColors.primary,
      'client' => const Color(0xFF9C27B0),
      'operator' => AppColors.warning,
      _ => AppColors.textSecondary,
    };

class _OrgCodeTile extends StatelessWidget {
  final OrgCode code;
  final VoidCallback onDelete;

  const _OrgCodeTile({required this.code, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isInactive = code.isExpired || code.isFullyUsed;
    final roleColor = _roleColor(code.intendedRole);

    return Dismissible(
      key: ValueKey(code.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Opacity(
        opacity: isInactive ? 0.5 : 1.0,
        child: Card(
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.vpn_key, color: roleColor, size: 22),
            ),
            title: Row(
              children: [
                Text(code.code,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace', letterSpacing: 1.5)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    code.intendedRole.toUpperCase(),
                    style: TextStyle(
                      color: roleColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${code.useCount}/${code.maxUses} uses',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                if (code.expiresAt != null)
                  Text(
                    code.isExpired
                        ? 'Expired'
                        : 'Expires ${DateFormat.yMMMd().format(code.expiresAt!)}',
                    style: TextStyle(
                      color: code.isExpired
                          ? AppColors.error
                          : AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                if (code.notes != null && code.notes!.isNotEmpty)
                  Text(code.notes!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
            isThreeLine: true,
          ),
        ),
      ),
    );
  }
}

class _OrgCodeForm extends ConsumerStatefulWidget {
  const _OrgCodeForm();

  @override
  ConsumerState<_OrgCodeForm> createState() => _OrgCodeFormState();
}

class _OrgCodeFormState extends ConsumerState<_OrgCodeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  final _notesCtrl = TextEditingController();
  final _maxUsesCtrl = TextEditingController(text: '1');
  String _role = 'client';
  bool _singleUse = true;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: OrgCodeController.generateCode());
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _notesCtrl.dispose();
    _maxUsesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _expiresAt = date);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(orgCodeControllerProvider.notifier)
        .createCode(
          code: _codeCtrl.text.trim(),
          intendedRole: _role,
          maxUses: int.tryParse(_maxUsesCtrl.text) ?? 1,
          singleUse: _singleUse,
          expiresAt: _expiresAt,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
    if (success && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controllerState = ref.watch(orgCodeControllerProvider);
    final isLoading = controllerState is AsyncLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.createOrgCode,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeCtrl,
                decoration: InputDecoration(
                  labelText: l10n.orgCode,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() =>
                        _codeCtrl.text = OrgCodeController.generateCode()),
                  ),
                ),
                style: const TextStyle(
                    fontFamily: 'monospace', letterSpacing: 1.5),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: InputDecoration(labelText: l10n.intendedRole),
                dropdownColor: AppColors.surfaceVariant,
                items: const [
                  DropdownMenuItem(value: 'owner', child: Text('Owner')),
                  DropdownMenuItem(value: 'employee', child: Text('Employee')),
                  DropdownMenuItem(value: 'client', child: Text('Client')),
                  DropdownMenuItem(value: 'operator', child: Text('Operator')),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxUsesCtrl,
                decoration: InputDecoration(labelText: l10n.maxUses),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _singleUse,
                onChanged: (v) => setState(() => _singleUse = v),
                title:
                    Text(l10n.singleUse, style: const TextStyle(fontSize: 14)),
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primary,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _expiresAt != null
                      ? DateFormat.yMMMd().format(_expiresAt!)
                      : l10n.expirationDate,
                  style: TextStyle(
                    fontSize: 14,
                    color: _expiresAt != null
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
                trailing: const Icon(Icons.calendar_today,
                    color: AppColors.textSecondary, size: 20),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(labelText: l10n.notes),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
