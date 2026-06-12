import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_assets_section.dart';
import 'package:vortice_app/features/clients/client_capability_switchboard_section.dart';
import 'package:vortice_app/features/clients/client_org_section.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/models/profile.dart';

class ClientDetailSheet extends ConsumerStatefulWidget {
  final Profile client;

  const ClientDetailSheet({super.key, required this.client});

  @override
  ConsumerState<ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends ConsumerState<ClientDetailSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.client.fullName);
    _emailCtrl = TextEditingController(text: widget.client.email);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final success = await ref
        .read(clientControllerProvider.notifier)
        .updateClient(widget.client.id, {
      'full_name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
    });
    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controllerState = ref.watch(clientControllerProvider);
    final isLoading = controllerState is AsyncLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.clientDetails,
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: Icon(_editing ? Icons.close : Icons.edit,
                      color: AppColors.primary),
                  onPressed: () => setState(() => _editing = !_editing),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_editing) ...[
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: l10n.fullName),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(labelText: l10n.email),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : _save,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ] else ...[
              _DetailRow(label: l10n.fullName, value: widget.client.fullName),
              _DetailRow(label: l10n.email, value: widget.client.email),
              _DetailRow(
                  label: l10n.language,
                  value: widget.client.preferredLanguage == 'es'
                      ? l10n.spanish
                      : l10n.english),
              const SizedBox(height: 8),
              ClientCapabilitySwitchboardSection(clientId: widget.client.id),
              const SizedBox(height: 16),
              ClientOrgSection(client: widget.client),
              const SizedBox(height: 16),
              ClientAssetsSection(clientId: widget.client.id),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
