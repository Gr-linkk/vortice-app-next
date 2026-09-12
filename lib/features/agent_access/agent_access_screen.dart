import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/models/profile.dart';
import 'agent_access_repository.dart';
import 'agent_connection_setup.dart';
import 'agent_work_proposals_screen.dart';
import 'maintenance_documents_screen.dart';
import 'agent_plan_review_screen.dart';
import 'agent_pending_plans_screen.dart';
import 'package:vortice_app/features/checklist_builder/checklist_builder_repository.dart';

class AgentAccessScreen extends ConsumerWidget {
  const AgentAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authStatusProvider).profile;
    final session = ref.watch(sessionProvider);
    if (profile == null ||
        session?.user.id != profile.id ||
        ![
          UserRole.owner,
          UserRole.client,
          UserRole.clientAdmin,
        ].contains(profile.role)) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            isSpanish(context)
                ? 'Inicia sesión con una cuenta autorizada.'
                : 'Sign in with an authorized account.',
          ),
        ),
      );
    }
    return AgentAccessPanel(
      key: ValueKey(profile.id),
      repository: ref.watch(agentAccessRepositoryProvider),
      isOwner: profile.role == UserRole.owner,
      onChecklistReview: () => ref.invalidate(checklistLibraryProvider),
    );
  }
}

/// Account-keyed panel: no persisted keys, fetched records or offline queue.
class AgentAccessPanel extends StatefulWidget {
  const AgentAccessPanel({
    super.key,
    required this.repository,
    required this.isOwner,
    this.onChecklistReview,
  });
  final AgentAccessRepository repository;
  final bool isOwner;
  final VoidCallback? onChecklistReview;

  @override
  State<AgentAccessPanel> createState() => _AgentAccessPanelState();
}

class _AgentAccessPanelState extends State<AgentAccessPanel> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  Map<String, dynamic>? _mfaSetup;
  Map<String, dynamic>? _data;
  String? _fleet;
  String? _secret;
  String? _error;
  bool _drafts = false;
  bool _documents = false, _management = false;
  bool _trusted = false;
  bool _busy = false;
  int _generation = 0;
  bool get _canCreate =>
      !widget.isOwner ||
      (widget.repository.ownerVerified &&
          _data?['owner_verification_required'] != true);

  String t(String en, String es) => isSpanish(context) ? es : en;
  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final local = MaterialLocalizations.of(context);
    return '${local.formatMediumDate(date)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  List<Map<String, dynamic>> rows(String key) => ((_data?[key] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _secret = null;
    _mfaSetup = null;
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.repository.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        if (!rows('fleets').any((f) => f['id'] == _fleet)) _fleet = null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _error = t(
          'Could not load agent access. Check your connection and try again.',
          'No se pudo cargar el acceso. Revisa tu conexión e inténtalo de nuevo.',
        ),
      );
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_busy ||
        !_canCreate ||
        _fleet == null ||
        !_trusted ||
        _name.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _secret = null;
    });
    try {
      final result = await widget.repository.create(
        _fleet!,
        _name.text.trim(),
        _drafts,
        documents: _documents,
        management: _management,
      );
      if (!mounted) return;
      setState(() {
        _secret = result['token'] as String;
        _trusted = false;
        _name.clear();
      });
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = t(
          'Connection could not be confirmed. Refresh and disconnect any newly created connection before retrying.',
          'No se pudo confirmar la conexión. Actualiza y desconecta cualquier conexión nueva antes de reintentar.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareMfa() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final setup = await widget.repository.prepareOwnerVerification();
      if (mounted) setState(() => _mfaSetup = setup);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            'Could not start two-factor verification. Retry while online.',
            'No se pudo iniciar la verificación. Reintenta con conexión.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyMfa() async {
    if (_busy || _mfaSetup == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.verifyOwner(
        _mfaSetup!['id'] as String,
        _code.text.trim(),
      );
      if (mounted) {
        setState(() {
          _mfaSetup = null;
          _code.clear();
        });
        await _refresh();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            'Verification failed. Check the six-digit code and try again.',
            'No se pudo verificar. Revisa el código de seis dígitos e inténtalo de nuevo.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke({
    String? connection,
    String? fleet,
    bool all = false,
  }) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Disconnect agent access?', '¿Desconectar el acceso?')),
        content: Text(
          all
              ? t(
                  'This disconnects every current agent connection across all fleets.',
                  'Esto desconecta todos los agentes de todas las flotas.',
                )
              : fleet != null
              ? t(
                  'This disconnects every current agent connection for this fleet.',
                  'Esto desconecta todos los agentes de esta flota.',
                )
              : t(
                  'This key will stop working. Existing drafts will remain.',
                  'Esta clave dejará de funcionar. Los borradores existentes se conservarán.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Cancel', 'Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Disconnect', 'Desconectar')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _secret = null;
    });
    try {
      await widget.repository.revoke(
        connection: connection,
        fleet: fleet,
        all: all,
      );
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            'Disconnect was not confirmed. Retry while online.',
            'No se confirmó la desconexión. Reintenta con conexión.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _activity(Map<String, dynamic> event) => switch (event['outcome']) {
    'revoked' => t('Disconnected', 'Desconectado'),
    'read' => event['action'] == 'connection_test'
        ? t('Host connection verified', 'Conexión del agente verificada')
        : t('Fleet information read', 'Información de flota consultada'),
    'replayed' => t(
      'Retry; no duplicate change',
      'Reintento sin cambios duplicados',
    ),
    'rejected' => t('Request rejected', 'Solicitud rechazada'),
    _ =>
      event['action'] == 'connection'
          ? t('Connected', 'Conectado')
          : event['action'] == 'create_plan_draft'
          ? t(
              'Maintenance plan ready for review',
              'Plan de mantenimiento listo para revisar',
            )
          : event['action'] == 'create_checklist_draft'
          ? t(
              'Checklist draft ready for review',
              'Borrador de lista listo para revisar',
            )
          : event['action'] == 'create_work_order_draft'
          ? t('Work-order draft created', 'Borrador de orden creado')
          : event['work_proposal'] == true
          ? t('Work proposal for review', 'Propuesta de trabajo para revisar')
          : t('Work order updated', 'Orden de trabajo actualizada'),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Connections', 'Conexiones')),
        actions: [
          IconButton(
            tooltip: t('Refresh', 'Actualizar'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            tooltip: t('Disconnect options', 'Opciones de desconexión'),
            onSelected: (choice) => _revoke(
              fleet: choice == 'fleet' ? _fleet : null,
              all: choice == 'all',
            ),
            itemBuilder: (_) => [
              if (_fleet != null)
                PopupMenuItem(
                  value: 'fleet',
                  child: Text(
                    t('Disconnect this fleet', 'Desconectar esta flota'),
                  ),
                ),
              if (widget.isOwner)
                PopupMenuItem(
                  value: 'all',
                  child: Text(
                    t('Disconnect all fleets', 'Desconectar todas las flotas'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          AgentConnectionSetup(es: isSpanish(context)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_canCreate)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(
                        'Verify owner access',
                        'Verifica tu acceso de propietario',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      t(
                        'Two-factor verification is required to create owner connections. You can still disconnect existing agents.',
                        'Se requiere verificación de dos factores para crear conexiones del propietario. Puedes desconectar agentes existentes.',
                      ),
                    ),
                    if (_mfaSetup == null)
                      FilledButton(
                        onPressed: _busy ? null : _prepareMfa,
                        child: Text(
                          t(
                            'Verify with authenticator',
                            'Verificar con autenticador',
                          ),
                        ),
                      )
                    else ...[
                      if (_mfaSetup!['secret'] != null) ...[
                        Text(
                          t(
                            'Add this setup key to your authenticator as a time-based account named Vortice Next. Keep the authenticator for future logins. Setup may sign out your other sessions.',
                            'Agrega esta clave a tu autenticador como una cuenta basada en tiempo llamada Vortice Next. Conserva el autenticador para futuros accesos. La configuración puede cerrar tus otras sesiones.',
                          ),
                        ),
                        SelectableText(_mfaSetup!['secret'] as String),
                      ],
                      TextField(
                        controller: _code,
                        enabled: !_busy,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: t(
                            'Six-digit code',
                            'Código de seis dígitos',
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _verifyMfa,
                        child: Text(t('Verify code', 'Verificar código')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_secret != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(
                        'Save your connection key',
                        'Guarda tu clave de conexión',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      t(
                        'Shown once. Store it in your agent’s secret settings, never in a chat. Anyone with this key can use its permissions. It expires in 7 days.',
                        'Se muestra una sola vez. Guárdala en los secretos del agente, nunca en un chat. Cualquiera con esta clave puede usar sus permisos. Caduca en 7 días.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(_secret!),
                    TextButton(
                      onPressed: () => setState(() => _secret = null),
                      child: Text(t('I saved the key', 'Ya guardé la clave')),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            t('Connect a trusted agent', 'Conecta un agente de confianza'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            t(
              'Your agent receives fleet names and maintenance plans. Choose a provider you trust; its privacy and retention rules apply.',
              'Tu agente recibe nombres de activos y planes de mantenimiento. Elige un proveedor de confianza; se aplican sus reglas de privacidad y retención.',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_fleet),
            initialValue: _fleet,
            isExpanded: true,
            decoration: InputDecoration(labelText: t('Fleet', 'Flota')),
            items: rows('fleets')
                .map(
                  (f) => DropdownMenuItem(
                    value: f['id'] as String,
                    child: Text(f['name'] as String),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _fleet = value;
                    _trusted = false;
                  }),
          ),
          if (_data != null && rows('fleets').isEmpty)
            Text(
              t(
                'Add an asset to your fleet before connecting an agent.',
                'Agrega un activo a tu flota antes de conectar un agente.',
              ),
            ),
          const SizedBox(height: 12),
          if (_fleet != null)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MaintenanceDocumentsScreen(
                          fleet: _fleet!,
                          fleetName:
                              rows(
                                    'fleets',
                                  ).firstWhere((f) => f['id'] == _fleet)['name']
                                  as String,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(
                t(
                  'Scan maintenance documents',
                  'Escanear documentos de mantenimiento',
                ),
              ),
            ),
          if (_fleet != null)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AgentPendingPlansScreen(fleet: _fleet!),
                      ),
                    ),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(t('Plans to review', 'Planes por revisar')),
            ),
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: t('Name', 'Nombre'),
              hintText: t(
                'My maintenance assistant',
                'Mi asistente de mantenimiento',
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _drafts,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _drafts = v;
                    _trusted = false;
                  }),
            title: Text(
              t('Allow work-order drafts', 'Permitir borradores de órdenes'),
            ),
            subtitle: Text(
              t(
                'Creates unassigned drafts for review in Work.',
                'Crea borradores sin asignar para revisar en Trabajo.',
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _documents,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _documents = v;
                    _trusted = false;
                  }),
            title: Text(
              t(
                'Allow documents and maintenance drafts',
                'Permitir documentos y borradores de mantenimiento',
              ),
            ),
            subtitle: Text(
              t(
                'Reads manuals and drafts maintenance plans, PM checks and pre-ops. You review, edit and activate them in the app.',
                'Lee manuales y prepara planes, listas PM y preoperativas. Tú los revisas, editas y activas en la app.',
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _management,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _management = v;
                    _trusted = false;
                  }),
            title: Text(
              t('Allow work proposals', 'Permitir propuestas de trabajo'),
            ),
            subtitle: Text(
              t(
                'Proposes staff, schedules and scope. You review and apply each change in Agents. Cannot sign, approve completion or invoice.',
                'Propone personal, horarios y alcance. Revisas y aplicas cada cambio en Agentes. No puede firmar, aprobar la finalización ni facturar.',
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _trusted,
            onChanged: _busy
                ? null
                : (v) => setState(() => _trusted = v ?? false),
            title: Text(
              t(
                'I trust this agent and allow it to receive this fleet’s data for 7 days.',
                'Confío en este agente y autorizo que reciba los datos de esta flota durante 7 días.',
              ),
            ),
          ),
          FilledButton(
            onPressed:
                !_busy &&
                    _canCreate &&
                    _trusted &&
                    _fleet != null &&
                    _name.text.trim().isNotEmpty &&
                    _secret == null
                ? _create
                : null,
            child: Text(t('Create connection key', 'Crear clave de conexión')),
          ),
          const SizedBox(height: 24),
          Text(
            t('Connections', 'Conexiones'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_data != null && rows('connections').isEmpty)
            Text(t('No connections yet.', 'Aún no hay conexiones.')),
          if (_data?['connections_truncated'] == true)
            Text(
              t(
                'Showing 200 connections, active first. Fleet disconnect also revokes connections not shown here.',
                'Se muestran 200 conexiones, primero las activas. Desconectar la flota también revoca las conexiones no visibles.',
              ),
            ),
          for (final connection in rows('connections'))
            Card(
              child: ListTile(
                title: Text(connection['label'] as String),
                subtitle: Text(
                  [
                    rows('fleets')
                            .where((f) => f['id'] == connection['client_id'])
                            .map((f) => f['name'])
                            .firstOrNull ??
                        '',
                    if (connection['actor_name'] != null)
                      '${t('Authorized by', 'Autorizado por')} ${connection['actor_name']}',
                    connection['last_tested_at'] == null
                        ? t('Host not tested yet', 'Agente aún sin comprobar')
                        : '${t('Last successful host check', 'Última comprobación del agente')}: ${_date(connection['last_tested_at'])}',
                    connection['revoked_at'] != null
                        ? t('Disconnected', 'Desconectado')
                        : DateTime.tryParse(
                                connection['expires_at'] as String,
                              )?.isBefore(DateTime.now()) ==
                              true
                        ? t('Expired', 'Caducado')
                        : '${t('Fleet maintenance', 'Mantenimiento de flota')}${connection['allow_drafts'] == true ? t(' · Work drafts', ' · Borradores de órdenes') : ''}${connection['allow_documents'] == true ? t(' · Documents', ' · Documentos') : ''}${connection['allow_management'] == true ? t(' · Management', ' · Gestión') : ''} · ${t('Expires', 'Caduca')} ${_date(connection['expires_at'])}',
                  ].join('\n'),
                ),
                trailing: connection['revoked_at'] == null
                    ? IconButton(
                        tooltip: t('Disconnect', 'Desconectar'),
                        onPressed: _busy
                            ? null
                            : () => _revoke(
                                connection: connection['id'] as String,
                              ),
                        icon: const Icon(Icons.link_off),
                      )
                    : null,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            t('Recent activity', 'Actividad reciente'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final event in rows('activity'))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${event['label']} · ${_activity(event)}'),
              subtitle: Text(_date(event['created_at'])),
              onTap: event['result_id'] == null
                  ? null
                  : () {
                      if (event['action'] == 'create_plan_draft') {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AgentPlanReviewScreen(
                              id: event['result_id'] as String,
                            ),
                          ),
                        );
                      } else if (event['work_proposal'] == true) {
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AgentWorkProposalsScreen(proposalId: event['result_id'] as String)));
                      } else if (event['action'] == 'create_checklist_draft') {
                        widget.onChecklistReview?.call();
                        context.push('/checklist-library');
                      } else {
                        context.push('/maintenance/jobs/${event['result_id']}');
                      }
                    },
              trailing: event['result_id'] == null
                  ? null
                  : const Icon(Icons.chevron_right),
            ),
        ],
      ),
    );
  }
}
