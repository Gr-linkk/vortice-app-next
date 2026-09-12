import 'package:flutter/material.dart';
import 'package:vortice_app/core/user_feedback.dart';

class DevLoginAccount {
  const DevLoginAccount(this.email, this.en, this.es, this.role, this.group);
  final String email, en, es, role;
  final int group;
  String label(bool spanish) => spanish ? es : en;
}

/// Internal demo personas; each account keeps its actual saved membership.
/// Credentials come only from the private debug build configuration.
const knownDevLoginAccounts = [
  DevLoginAccount('demo_fleet_owner@vortice.dev', 'Demo fleet owner', 'Propietario de flota demo', 'company_owner', 3),
  DevLoginAccount('demo_fleet_supervisor@vortice.dev', 'Demo fleet supervisor', 'Supervisor de flota demo', 'supervisor', 3),
  DevLoginAccount('demo_fleet_mechanic@vortice.dev', 'Demo fleet mechanic', 'Mecánico de flota demo', 'mechanic', 3),
  DevLoginAccount('demo_fleet_operator@vortice.dev', 'Demo fleet operator', 'Operador de flota demo', 'operator', 3),
  DevLoginAccount('demo_service_owner@vortice.dev', 'Demo service company owner', 'Propietario del servicio demo', 'company_owner', 3),
  DevLoginAccount(
    'owner@vortice.dev',
    'Provider owner / administrator',
    'Propietario / administrador del proveedor',
    'owner',
    0,
  ),
  DevLoginAccount(
    'tech@vortice.dev',
    'Provider technician',
    'Técnico del proveedor',
    'employee',
    0,
  ),
  DevLoginAccount(
    'paradise@vortice.dev',
    'Company manager',
    'Responsable de la empresa',
    'client_admin',
    1,
  ),
  DevLoginAccount(
    'client@vortice.dev',
    'Second company owner',
    'Propietario de otra empresa',
    'client',
    1,
  ),
  DevLoginAccount(
    'client_mechanic@vortice.dev',
    'Company mechanic',
    'Mecánico de la empresa',
    'client_mechanic',
    1,
  ),
  DevLoginAccount(
    'operator@vortice.dev',
    'Company operator',
    'Operador de la empresa',
    'operator',
    1,
  ),
];

List<DevLoginAccount> devLoginAccounts(Iterable<String> configuredEmails) {
  final configured = configuredEmails.toSet();
  final known = knownDevLoginAccounts.map((account) => account.email).toSet();
  final extra =
      configuredEmails.where((email) => !known.contains(email)).toSet().toList()
        ..sort();
  return [
    ...knownDevLoginAccounts.where((account) => account.group != 3 || configured.contains(account.email)),
    for (final email in extra)
      DevLoginAccount(
        email,
        'Additional test profile',
        'Otro perfil de prueba',
        '',
        2,
      ),
  ];
}

class DevLoginAccountSheet extends StatelessWidget {
  const DevLoginAccountSheet({
    super.key,
    required this.configuredEmails,
    required this.onSelected,
    this.currentEmail,
  });
  final Set<String> configuredEmails;
  final ValueChanged<String> onSelected;
  final String? currentEmail;

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final accounts = devLoginAccounts(configuredEmails);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Text(
              es ? 'Cuentas de prueba' : 'Test accounts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              es
                  ? 'Elige una cuenta. El trabajo guardado se conserva en su cuenta.'
                  : 'Choose an account. Saved work stays with its account.',
            ),
            for (final group in [3, 0, 1, 2])
              if (accounts.any((account) => account.group == group)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(switch (group) {
                    3 => es ? 'Empresas demo nuevas' : 'New demo companies',
                    0 => es ? 'Empresa proveedora' : 'Service provider',
                    1 => es ? 'Empresas clientes' : 'Client companies',
                    _ =>
                      es
                          ? 'Otros perfiles configurados'
                          : 'Other configured profiles',
                  }, style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final account in accounts.where(
                  (account) => account.group == group,
                ))
                  Card(
                    child: ListTile(
                      key: ValueKey('dev-account:${account.email}'),
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(account.label(es)),
                      subtitle: Text(
                        [
                          account.email,
                          if (account.role.isNotEmpty)
                            '${es ? 'Rol actual' : 'Current role'}: ${account.role}',
                          if (account.role.isEmpty)
                            es
                                ? 'El perfil guardado determina los permisos.'
                                : 'The saved profile determines permissions.',
                          if (!configuredEmails.contains(account.email))
                            es
                                ? 'Acceso no configurado en esta compilación.'
                                : 'Sign-in is not configured in this build.',
                          if (account.email == currentEmail)
                            es ? 'Cuenta actual' : 'Current account',
                        ].join('\n'),
                      ),
                      enabled:
                          configuredEmails.contains(account.email) &&
                          account.email != currentEmail,
                      onTap:
                          configuredEmails.contains(account.email) &&
                              account.email != currentEmail
                          ? () => onSelected(account.email)
                          : null,
                    ),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}
