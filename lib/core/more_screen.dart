import 'package:vortice_app/features/auth/sign_out_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/app_navigation.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

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
    final es = isSpanish(context);
    final roomyText = MediaQuery.textScalerOf(context).scale(14) > 18;
    final query = _search.text.trim().toLowerCase();
    final tools = toolDestinations(profile.role)
        .where(
          (item) =>
              '${item.en} ${item.es} ${item.description} ${item.descriptionEs}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Más' : 'More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: es ? 'Buscar' : 'Find a tool',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: es ? 'Borrar búsqueda' : 'Clear search',
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
                es
                    ? 'No hay resultados. Prueba otra palabra.'
                    : 'No matching tools. Try another word.',
              ),
            ),
          for (final group in [0, 1])
            if (tools.any((item) => item.group == group)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  group == 0
                      ? (es
                            ? 'Servicio y mantenimiento'
                            : 'Service & maintenance')
                      : (es ? 'Administración' : 'Administration'),
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
                        title: Text(item.label(es)),
                        subtitle: Text(
                          item.detail(es),
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
            const SizedBox(height: 20),
            Text(
              es ? 'Tu cuenta' : 'Your account',
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
                    leading: const Icon(Icons.language),
                    title: Text(es ? 'Idioma / Language' : 'Language / Idioma'),
                    subtitle: Text(es ? 'Español' : 'English'),
                    trailing: Text(es ? 'English' : 'Español'),
                    onTap: () => ref
                        .read(localeProvider.notifier)
                        .setLocale(Locale(es ? 'en' : 'es')),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: Text(es ? 'Cerrar sesión' : 'Sign out'),
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
