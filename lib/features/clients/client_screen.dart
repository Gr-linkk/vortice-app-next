import 'package:vortice_app/core/user_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/clients/client_list_tile.dart';
import 'package:vortice_app/features/clients/client_provider.dart';
import 'package:vortice_app/features/clients/client_screen_support.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

class ClientScreen extends ConsumerStatefulWidget {
  const ClientScreen({super.key});

  @override
  ConsumerState<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends ConsumerState<ClientScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final clientsAsync = ref.watch(clientsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showClientInviteSheet(context),
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
              Text(friendlyError(context, err)),
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
              itemBuilder: (_, i) => ClientListTile(client: filtered[i]),
            ),
          );
        },
      ),
    );
  }
}
