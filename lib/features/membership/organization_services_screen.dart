import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'company_purpose.dart';
import 'membership_provider.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/membership/organization_work_provider.dart';
import 'package:vortice_app/features/work_orders/work_order_provider.dart';

class OrganizationServicesScreen extends ConsumerStatefulWidget {
  const OrganizationServicesScreen({super.key});
  @override
  ConsumerState<OrganizationServicesScreen> createState() =>
      _OrganizationServicesScreenState();
}

class _OrganizationServicesScreenState
    extends ConsumerState<OrganizationServicesScreen> {
  bool _busy = false;
  String _t(String en, String es) => isSpanish(context) ? es : en;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(organizationServiceConfigurationProvider);
      ref.invalidate(organizationServiceRequestContextProvider);
      ref.invalidate(organizationContextProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(context, error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Connect a customer', 'Conectar un cliente')),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: _t(
              'Customer company code',
              'Código de la empresa cliente',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('Cancel', 'Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(_t('Request connection', 'Solicitar conexión')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code != null && code.trim().isNotEmpty) {
      await _run(
        () => ref.read(organizationWorkRepositoryProvider).propose(code),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_t('Company services', 'Servicios de la empresa')),
    ),
    body: ref
        .watch(organizationServiceConfigurationProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AppErrorState(
            error: error,
            onRetry: () =>
                ref.invalidate(organizationServiceConfigurationProvider),
          ),
          data: (data) {
            final settings = Map<String, dynamic>.from(data['settings'] as Map);
            final owner = data['can_manage'] == true;
            final admin = data['can_admin'] == true;
            final org = data['organization_id'];
            final provider = settings['provider_enabled'] == true;
            final billing = settings['billing_enabled'] == true;
            final purpose = CompanyPurpose.parse(
              settings['company_purpose'] as String?,
            );
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  purpose == CompanyPurpose.fleet || !provider
                      ? _t(
                          'Maintain your own equipment. Connect with a service provider when you need outside work.',
                          'Mantén tus propios equipos. Conecta con un proveedor cuando necesites trabajo externo.',
                        )
                      : _t(
                          'Maintain your own equipment and work with customer companies.',
                          'Mantén tus propios equipos y trabaja con empresas clientes.',
                        ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                CompanyPurposePicker(
                  value: purpose,
                  spanish: isSpanish(context),
                  onChanged: !owner || _busy
                      ? null
                      : (value) => _run(
                          () => ref
                              .read(membershipRepositoryProvider)
                              .setPurpose(value),
                        ),
                ),
                const SizedBox(height: 16),
                if (purpose != CompanyPurpose.fleet || billing)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: billing,
                    title: Text(
                      _t(
                        'Enable company billing',
                        'Activar facturación de empresa',
                      ),
                    ),
                    subtitle: Text(
                      purpose == CompanyPurpose.fleet
                          ? _t(
                              'Customer invoices are for service providers. Turn this off to match your company choice.',
                              'Las facturas a clientes son para proveedores de servicios. Desactiva esta opción para que coincida con tu empresa.',
                            )
                          : _t(
                              'For customer work only. People also need Billing permission to manage invoices.',
                              'Solo para trabajos de clientes. También se necesita permiso de facturación para gestionar facturas.',
                            ),
                    ),
                    onChanged:
                        !owner ||
                            _busy ||
                            (purpose == CompanyPurpose.fleet && !billing)
                        ? null
                        : (value) => _run(
                            () => ref
                                .read(organizationWorkRepositoryProvider)
                                .configure(provider, value),
                          ),
                  ),
                const Divider(height: 32),
                Text(
                  _t('Your company code', 'Código de tu empresa'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: SelectableText(settings['connection_code'] as String),
                  subtitle: Text(
                    _t(
                      'Share with a service provider. You approve the connection before work can be requested.',
                      'Compártelo con un proveedor. Debes aprobar la conexión antes de solicitar trabajo.',
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: _t('Copy company code', 'Copiar código'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: settings['connection_code'] as String,
                        ),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _t('Company code copied', 'Código copiado'),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
                if (provider && admin)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.link),
                    label: Text(
                      _t('Connect a customer', 'Conectar un cliente'),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  _t('Connections', 'Conexiones'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final raw in data['relationships'] as List)
                  Builder(
                    builder: (context) {
                      final relation = Map<String, dynamic>.from(raw as Map);
                      final incoming =
                          relation['client_organization_id'] == org;
                      final status = relation['status'] as String;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          (incoming
                                  ? relation['provider_name']
                                  : relation['client_name'])
                              as String,
                        ),
                        subtitle: Text(
                          status == 'active'
                              ? _t('Connected', 'Conectado')
                              : status == 'proposed'
                              ? _t(
                                  'Awaiting approval',
                                  'Pendiente de aprobación',
                                )
                              : _t('Connection ended', 'Conexión finalizada'),
                        ),
                        trailing: status == 'proposed' && incoming && admin
                            ? TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => ref
                                            .read(
                                              organizationWorkRepositoryProvider,
                                            )
                                            .relationship(
                                              relation['provider_organization_id']
                                                  as String,
                                              relation['client_organization_id']
                                                  as String,
                                              'accept',
                                            ),
                                      ),
                                child: Text(_t('Accept', 'Aceptar')),
                              )
                            : status == 'active' && admin
                            ? IconButton(
                                tooltip: _t(
                                  'End connection',
                                  'Finalizar conexión',
                                ),
                                icon: const Icon(Icons.link_off),
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => ref
                                            .read(
                                              organizationWorkRepositoryProvider,
                                            )
                                            .relationship(
                                              relation['provider_organization_id']
                                                  as String,
                                              relation['client_organization_id']
                                                  as String,
                                              'revoke',
                                            ),
                                      ),
                              )
                            : null,
                      );
                    },
                  ),
                const Divider(height: 32),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => showOrganizationServiceRequest(context),
                  icon: const Icon(Icons.add_task),
                  label: Text(_t('Request service', 'Solicitar servicio')),
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    'Service requests open in Work Orders with your other work.',
                    'Las solicitudes de servicio se abren en Órdenes de trabajo junto con tus otros trabajos.',
                  ),
                ),
              ],
            );
          },
        ),
  );
}

Future<void> showOrganizationServiceRequest(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const OrganizationServiceRequestSheet(),
    );

class OrganizationServiceRequestSheet extends ConsumerStatefulWidget {
  const OrganizationServiceRequestSheet({super.key});
  @override
  ConsumerState<OrganizationServiceRequestSheet> createState() =>
      _OrganizationServiceRequestSheetState();
}

class _OrganizationServiceRequestSheetState
    extends ConsumerState<OrganizationServiceRequestSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _operation = const Uuid().v4();
  String? _provider;
  String? _asset;
  String? _error;
  bool _busy = false;
  String _t(String en, String es) => isSpanish(context) ? es : en;
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy ||
        _provider == null ||
        _asset == null ||
        _title.text.trim().length < 3) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(organizationWorkRepositoryProvider)
          .request(_operation, _provider!, _asset!, _title.text, _note.text);
      ref.invalidate(workOrdersProvider);
      if (mounted) {
        final router = GoRouter.of(context);
        Navigator.pop(context);
        router.push('/work-orders/$id');
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      20,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: ref
          .watch(organizationServiceRequestContextProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => AppErrorState(
              error: error,
              onRetry: () =>
                  ref.invalidate(organizationServiceRequestContextProvider),
            ),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('Request service', 'Solicitar servicio'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                if ((data['providers'] as List).isEmpty)
                  Text(
                    _t(
                      'Connect and approve a service provider in Company services first.',
                      'Conecta y aprueba un proveedor en Servicios de la empresa primero.',
                    ),
                  )
                else ...[
                  AppDropdownField<String>(
                    isExpanded: true,
                    initialValue: _provider,
                    decoration: InputDecoration(
                      labelText: _t('Provider', 'Proveedor'),
                    ),
                    items: (data['providers'] as List)
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['relationship_id'] as String,
                            child: Text(p['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _provider = value),
                  ),
                  const SizedBox(height: 16),
                  AppDropdownField<String>(
                    isExpanded: true,
                    initialValue: _asset,
                    decoration: InputDecoration(
                      labelText: _t('Equipment', 'Equipo'),
                    ),
                    items: (data['assets'] as List)
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _asset = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _title,
                    enabled: !_busy,
                    maxLength: 160,
                    decoration: InputDecoration(
                      labelText: _t('Work needed', 'Trabajo necesario'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _note,
                    enabled: !_busy,
                    maxLines: 3,
                    maxLength: 4000,
                    decoration: InputDecoration(
                      labelText: _t(
                        'Request details',
                        'Detalles de la solicitud',
                      ),
                    ),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed:
                        _busy ||
                            _provider == null ||
                            _asset == null ||
                            _title.text.trim().length < 3
                        ? null
                        : _submit,
                    child: Text(
                      _busy
                          ? _t('Creating…', 'Creando…')
                          : _t('Create work order', 'Crear orden de trabajo'),
                    ),
                  ),
                ],
              ],
            ),
          ),
    ),
  );
}
