import 'package:vortice_app/features/auth/sign_out_button.dart';
import 'package:vortice_app/features/auth/dev_login_switch.dart';
import 'package:vortice_app/core/appearance_settings.dart';
import 'package:vortice_app/sync/field_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/language_picker.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/agent_access/agent_workspace_screen.dart';
import 'package:vortice_app/models/profile.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});
  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authStatusProvider).profile;
    if (profile == null) return const SizedBox.shrink();
    final locale = ref.watch(localeProvider);
    final es = isSpanish(context);
    final fr = isFrench(context);
    final roomyText = MediaQuery.textScalerOf(context).scale(14) > 18;
    final query = _search.text.trim().toLowerCase();
    final tools = toolDestinations(profile.role)
        .where(
          (item) =>
              !profile.membershipManaged ||
              (item.route != '/org/admin' &&
                  !item.route.endsWith('/service-requests') &&
                  (!item.route.endsWith('/invoices') ||
                      profile.canInOrganization('billing'))),
        )
        .where(
          (item) =>
              '${item.en} ${item.es} ${item.fr} ${item.description} ${item.descriptionEs} ${item.descriptionFr}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(localizedText(context, 'More', 'Más', 'Plus')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: Text(
              localizedText(
                context,
                'Your company',
                'Tu empresa',
                'Votre entreprise',
              ),
            ),
            subtitle: Text(
              localizedText(
                context,
                'Membership, roles and companies',
                'Miembros, roles y empresas',
                'Membres, rôles et entreprises',
              ),
            ),
            onTap: () => context.push('/company'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(
              localizedText(
                context,
                'Saved work and sync',
                'Guardado y sincronización',
                'Travail enregistré et synchronisation',
              ),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FieldQueueScreen()),
            ),
          ),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: localizedText(
                context,
                'Find a tool',
                'Buscar',
                'Rechercher un outil',
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: localizedText(
                        context,
                        'Clear search',
                        'Borrar búsqueda',
                        'Effacer la recherche',
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (tools.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                localizedText(
                  context,
                  'No matching tools. Try another word.',
                  'No hay resultados. Prueba otra palabra.',
                  'Aucun outil trouvé. Essayez un autre mot.',
                ),
              ),
            ),
          for (final group in [0, 1])
            if (tools.any((item) => item.group == group)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  group == 0
                      ? localizedText(
                          context,
                          'Service & maintenance',
                          'Servicio y mantenimiento',
                          'Service et entretien',
                        )
                      : localizedText(
                          context,
                          'Administration',
                          'Administración',
                          'Administration',
                        ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final item in tools.where(
                      (item) => item.group == group,
                    ))
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: roomyText ? null : Icon(item.icon),
                        title: Text(item.label(es, french: fr)),
                        subtitle: Text(
                          item.detail(es, french: fr),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        trailing: roomyText
                            ? null
                            : const Icon(Icons.chevron_right),
                        onTap: () => context.push(item.route),
                      ),
                  ],
                ),
              ),
            ],
          if (query.isEmpty) ...[
            const DevAccountSwitchEntry(),
            const SizedBox(height: 20),
            Text(
              localizedText(context, 'Settings', 'Configuración', 'Paramètres'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: Text(
                      localizedText(
                        context,
                        'Appearance',
                        'Apariencia',
                        'Apparence',
                      ),
                    ),
                    subtitle: Text(
                      localizedText(
                        context,
                        'Light, Dark or System',
                        'Claro, oscuro o sistema',
                        'Clair, sombre ou système',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AppearanceSettingsScreen(),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(AppLocalizations.of(context).language),
                    subtitle: Text(languageName(locale)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLanguagePicker(context, ref),
                  ),
                  if ([
                    UserRole.owner,
                    UserRole.client,
                    UserRole.clientAdmin,
                  ].contains(profile.role))
                    ListTile(
                      leading: const Icon(Icons.smart_toy_outlined),
                      title: Text(
                        localizedText(
                          context,
                          'Agent workspace',
                          'Espacio de agentes',
                          'Espace des agents',
                        ),
                      ),
                      subtitle: Text(
                        localizedText(
                          context,
                          'Manuals, plans and review',
                          'Manuales, planes y revisión',
                          'Manuels, plans et révision',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AgentWorkspaceScreen(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              localizedText(
                context,
                'Your account',
                'Tu cuenta',
                'Votre compte',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(profile.fullName),
                    subtitle: Text(profile.email),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(
                      localizedText(
                        context,
                        'Sign out',
                        'Cerrar sesión',
                        'Se déconnecter',
                      ),
                    ),
                    onTap: () => confirmSignOut(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Vórtice Next · ${AppConstants.appVersion}',
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
