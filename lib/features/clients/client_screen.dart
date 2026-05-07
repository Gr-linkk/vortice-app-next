import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/core/asset_icons.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart' as sb;
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/models/asset.dart';
import 'package:vortice_app/models/client_capability.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/models/subscription_tier.dart';

class ClientScreen extends ConsumerStatefulWidget {
  const ClientScreen({super.key});

  @override
  ConsumerState<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends ConsumerState<ClientScreen> {
  String _searchQuery = '';

  void _showInviteSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _InviteClientSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final clientsAsync = ref.watch(clientsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showInviteSheet,
        icon: const Icon(Icons.person_add),
        label: const Text("Invite Client"),
        backgroundColor: AppColors.primary,
      ),
      appBar: AppBar(
        title: Text(l10n.clientsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchClients,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: clientsAsync.when(
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
                onPressed: () => ref.invalidate(clientsProvider),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
        data: (clients) {
          final filtered = clients.where((c) {
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            return c.fullName.toLowerCase().contains(q) ||
                c.email.toLowerCase().contains(q);
          }).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(l10n.noClients,
                  style: const TextStyle(color: AppColors.textSecondary)),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(clientsProvider),
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) => _ClientTile(client: filtered[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ClientTile extends ConsumerWidget {
  final Profile client;
  const _ClientTile({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final assetCount = ref.watch(clientAssetCountProvider(client.id));
    final woCount = ref.watch(clientWorkOrderCountProvider(client.id));

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(Icons.person, color: AppColors.primary, size: 22),
        ),
        title: Text(client.fullName,
            style: Theme.of(context).textTheme.titleSmall),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(client.email,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            Row(
              children: [
                Text(
                  '${assetCount.valueOrNull ?? 0} ${l10n.navAssets}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(width: 12),
                Text(
                  '${woCount.valueOrNull ?? 0} ${l10n.navWorkOrders}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () => _showClientDetail(context, ref, l10n, client),
        isThreeLine: true,
      ),
    );
  }

  void _showClientDetail(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, Profile client) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ClientDetailSheet(client: client),
    );
  }
}

class _ClientDetailSheet extends ConsumerStatefulWidget {
  final Profile client;
  const _ClientDetailSheet({required this.client});

  @override
  ConsumerState<_ClientDetailSheet> createState() => _ClientDetailSheetState();
}

class _ClientDetailSheetState extends ConsumerState<_ClientDetailSheet> {
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
              _TierSelector(client: widget.client),
              const SizedBox(height: 16),
              _ClientCapabilitySwitchboardSection(clientId: widget.client.id),
              const SizedBox(height: 16),
              _OrgSection(client: widget.client),
              const SizedBox(height: 16),
              _ClientAssetsSection(clientId: widget.client.id),
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

// ── Tier selector (owner only) ──────────────────────────────────────────────

class _TierSelector extends ConsumerStatefulWidget {
  final Profile client;
  const _TierSelector({required this.client});

  @override
  ConsumerState<_TierSelector> createState() => _TierSelectorState();
}

class _TierSelectorState extends ConsumerState<_TierSelector> {
  bool _saving = false;

  Future<void> _saveTier(SubscriptionTier tier) async {
    setState(() => _saving = true);
    final success = await ref
        .read(clientControllerProvider.notifier)
        .updateClient(widget.client.id, {'subscription_tier': tier.value});
    if (success && mounted) {
      setState(() => _saving = false);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTier = widget.client.subscriptionTier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Legacy subscription tier',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Text(
          'Kept for existing billing labels; use Service Switchboard for workflow access.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SubscriptionTier.values
              .where((t) => t != SubscriptionTier.predictive)
              .map((tier) {
            final selected = tier == currentTier;
            return ChoiceChip(
              label: Text(tier.displayName),
              selected: selected,
              onSelected: _saving
                  ? null
                  : (sel) {
                      if (sel && !selected) _saveTier(tier);
                    },
              backgroundColor: AppColors.surface,
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 13,
              ),
              side: BorderSide(
                color: selected ? AppColors.primary : AppColors.divider,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Service switchboard (owner only) ────────────────────────────────────────

class _ClientCapabilitySwitchboardSection extends ConsumerWidget {
  final String clientId;
  const _ClientCapabilitySwitchboardSection({required this.clientId});

  static const _alwaysOnCapabilities = [
    'Assets & Documents',
    'Service History',
    'Invoices',
    'Request Vórtice Service',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final switchboardAsync = ref.watch(clientCapabilitiesProvider(clientId));
    final controllerState = ref.watch(clientCapabilityControllerProvider);
    final isSaving = controllerState is AsyncLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Service Switchboard',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        const Text(
          'Controls access to new workflow areas. Turning a switch off hides the workflow; existing records are preserved.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _alwaysOnCapabilities.map((label) {
            return Chip(
              avatar: const Icon(Icons.lock_open, size: 14),
              label: Text(label),
              backgroundColor: AppColors.surfaceVariant,
              side: const BorderSide(color: AppColors.cardBorder),
              labelStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        switchboardAsync.when(
          loading: () => const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => Row(
            children: [
              const Expanded(
                child: Text(
                  'Could not load service switches',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(clientCapabilitiesProvider(clientId)),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (switchboard) => Column(
            children: ClientCapability.values.map((capability) {
              final enabled = switchboard.isEnabled(capability);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: SwitchListTile.adaptive(
                  value: enabled,
                  onChanged: isSaving
                      ? null
                      : (value) async {
                          final success = await ref
                              .read(clientCapabilityControllerProvider.notifier)
                              .setCapability(
                                clientId: clientId,
                                capability: capability,
                                enabled: value,
                              );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? '${capability.label} ${value ? 'enabled' : 'disabled'}.'
                                    : 'Could not update ${capability.label}.',
                              ),
                            ),
                          );
                        },
                  title: Text(
                    capability.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    capability.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  dense: true,
                  activeThumbColor: AppColors.primary,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Assets for client provider ──────────────────────────────────────────────

final assetsByClientProvider =
    FutureProvider.family<List<Asset>, String>((ref, clientId) async {
  final data = await sb.supabase
      .from(AppConstants.tAssets)
      .select()
      .eq('client_id', clientId)
      .order('name');
  return (data as List)
      .map((e) => Asset.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Client assets section ─────────────────────────────────────────────────────

class _ClientAssetsSection extends ConsumerWidget {
  final String clientId;
  const _ClientAssetsSection({required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(assetsByClientProvider(clientId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vessels & Equipment',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 8),
        assetsAsync.when(
          loading: () => const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (_, __) => const Text('Could not load assets',
              style: TextStyle(color: AppColors.error, fontSize: 12)),
          data: (assets) {
            if (assets.isEmpty) {
              return const Text(
                'No assets assigned',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              );
            }
            return Column(
              children: assets
                  .map((asset) => InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/owner/assets/${asset.id}');
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(assetIconFor(asset.assetTypeId),
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(asset.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary)),
                                    if (asset.make != null ||
                                        asset.model != null)
                                      Text(
                                        [asset.make, asset.model]
                                            .whereType<String>()
                                            .join(' · '),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  size: 16, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

// ── Organization section (owner only) ────────────────────────────────────────

class _OrgSection extends ConsumerWidget {
  final Profile client;
  const _OrgSection({required this.client});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = client.orgId;

    // Client already has an org
    if (orgId != null) {
      final orgAsync = ref.watch(orgByIdProvider(orgId));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Organization',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          orgAsync.when(
            loading: () => const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => const Text('Could not load org',
                style: TextStyle(color: AppColors.error, fontSize: 13)),
            data: (org) => Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.business_outlined,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            org?.name ?? 'Unknown',
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textSecondary),
                  tooltip: 'Rename',
                  onPressed: () => _showRenameOrgDialog(
                      context, ref, orgId, org?.name ?? ''),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // No org — show create button
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Organization',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => _showCreateOrgDialog(context, ref),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create Organization'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  void _showRenameOrgDialog(
      BuildContext context, WidgetRef ref, String orgId, String currentName) {
    final nameCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Organization'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Organization name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await ref
                  .read(orgControllerProvider.notifier)
                  .renameOrg(orgId, name);
              ref.invalidate(clientsProvider);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCreateOrgDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController(text: client.fullName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Organization'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Organization name',
            hintText: 'e.g. Pacific Marine Services',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final orgId = await ref
                  .read(orgControllerProvider.notifier)
                  .createOrg(name, client.id);
              if (orgId != null) {
                ref.invalidate(clientsProvider);
                ref.invalidate(currentUserOrgProvider);
                if (context.mounted) {
                  Navigator.pop(context); // close the detail sheet
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Organization "$name" created'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ── Invite Client Sheet ────────────────────────────────────────────────────────

class _InviteClientSheet extends ConsumerStatefulWidget {
  const _InviteClientSheet();

  @override
  ConsumerState<_InviteClientSheet> createState() => _InviteClientSheetState();
}

class _InviteClientSheetState extends ConsumerState<_InviteClientSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _language = 'en';
  SubscriptionTier _tier = SubscriptionTier.free;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final email = _emailCtrl.text.trim();
    try {
      // Call Edge Function (uses service role key server-side — safe)
      final response = await sb.supabase.functions.invoke(
        'invite-client',
        body: {
          'email': email,
          'full_name': _nameCtrl.text.trim(),
          if (_phoneCtrl.text.trim().isNotEmpty)
            'phone': _phoneCtrl.text.trim(),
          'preferred_language': _language,
          'subscription_tier': _tier.value,
        },
      );
      if (response.data?['error'] != null) {
        throw Exception(response.data['error']);
      }
      ref.invalidate(clientsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invite sent to $email'),
            backgroundColor: AppColors.success,
          ),
        );
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Invite Client',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 16),
            // Language toggle
            Row(
              children: [
                const Text('Language',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(width: 16),
                ChoiceChip(
                  label: const Text('English'),
                  selected: _language == 'en',
                  onSelected: (_) => setState(() => _language = 'en'),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: _language == 'en'
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: _language == 'en'
                        ? AppColors.primary
                        : AppColors.divider,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Español'),
                  selected: _language == 'es',
                  onSelected: (_) => setState(() => _language = 'es'),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: _language == 'es'
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: _language == 'es'
                        ? AppColors.primary
                        : AppColors.divider,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Subscription tier
            const Text('Subscription Tier',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SubscriptionTier.values
                  .where((t) => t != SubscriptionTier.predictive)
                  .map((tier) {
                final selected = tier == _tier;
                return ChoiceChip(
                  label: Text(tier.displayName),
                  selected: selected,
                  onSelected: (sel) {
                    if (sel) setState(() => _tier = tier);
                  },
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color:
                        selected ? AppColors.primary : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.divider,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send Invite'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
