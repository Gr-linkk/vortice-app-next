import 'package:flutter/material.dart';
import 'package:vortice_app/core/app_dropdown_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/membership/membership_models.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/features/membership/membership_feedback.dart';
import 'package:vortice_app/sync/online_action_gate.dart';

class OrganizationScreen extends ConsumerStatefulWidget {
  const OrganizationScreen({super.key});
  @override
  ConsumerState<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends ConsumerState<OrganizationScreen> {
  bool _busy = false;
  String _t(String en, String es, [String? fr]) =>
      localizedText(context, en, es, fr ?? en);
  Future<void> _switch(String organizationId) async {
    if (!await requireOnlineAction(context, ref) || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(membershipRepositoryProvider)
          .selectOrganization(organizationId);
      if (!mounted) return;
      await refreshMembership(ref);
      if (mounted) context.go('/client/dashboard');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(membershipError(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(
    OrganizationMembership active, {
    TeamMember? member,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MembershipEditor(organization: active, member: member),
    );
    if (mounted) {
      ref.invalidate(organizationTeamProvider(active.organizationId));
      ref.invalidate(organizationContextProvider);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_t('Your company', 'Tu empresa', 'Votre entreprise')),
    ),
    body: ref
        .watch(organizationContextProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AppErrorState(
            error: error,
            onRetry: () => ref.invalidate(organizationContextProvider),
          ),
          data: (data) {
            final active = data.active;
            return RefreshIndicator(
              onRefresh: () async {
                await refreshMembership(ref);
              },
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (data.memberships.length > 1) ...[
                    AppDropdownField<String>(
                      initialValue: active?.organizationId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Active company',
                          'Empresa activa',
                          'Entreprise active',
                        ),
                      ),
                      items: data.memberships
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.organizationId,
                              child: Text(m.name),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null &&
                                  value != active?.organizationId) {
                                _switch(value);
                              }
                            },
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (active == null) ...[
                    Text(
                      _t(
                        'No company membership is available.',
                        'No hay una empresa disponible.',
                        'Aucune appartenance à une entreprise n’est disponible.',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Text(
                      active.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      active.roles
                          .map(
                            (key) => OrganizationRole.values
                                .firstWhere((r) => r.key == key)
                                .label(
                                  isSpanish(context),
                                  french: isFrench(context),
                                ),
                          )
                          .join(' · '),
                    ),
                    if (active.permissions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          active.permissions
                              .map(
                                (key) => OrganizationPermission.values
                                    .firstWhere((p) => p.key == key)
                                    .label(
                                      isSpanish(context),
                                      french: isFrench(context),
                                    ),
                              )
                              .join(' · '),
                        ),
                      ),
                    if (active.can('team_admin')) ...[
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _edit(active),
                        icon: const Icon(Icons.person_add_outlined),
                        label: Text(
                          _t(
                            'Invite teammate',
                            'Invitar a una persona',
                            'Inviter un membre de l’équipe',
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _team(active),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _t(
                            'A Company Owner or delegated team administrator manages invitations and access.',
                            'Un propietario o administrador autorizado gestiona las invitaciones y el acceso.',
                            'Un propriétaire ou un administrateur d’équipe délégué gère les invitations et les accès.',
                          ),
                        ),
                      ),
                  ],
                  const Divider(height: 32),
                  if (active != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.business_center_outlined),
                      title: Text(
                        _t(
                          'Company services',
                          'Servicios de la empresa',
                          'Services de l’entreprise',
                        ),
                      ),
                      subtitle: Text(
                        _t(
                          'Providers, customers and billing',
                          'Proveedores, clientes y facturación',
                          'Fournisseurs, clients et facturation',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _busy
                          ? null
                          : () => context.push('/company/services'),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_business_outlined),
                    title: Text(
                      _t(
                        'Join another company',
                        'Unirme a otra empresa',
                        'Rejoindre une autre entreprise',
                      ),
                    ),
                    subtitle: Text(
                      _t(
                        'Use an invitation code',
                        'Usar un código de invitación',
                        'Utiliser un code d’invitation',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => context.push('/company/join'),
                  ),
                ],
              ),
            );
          },
        ),
  );

  Widget _team(OrganizationMembership active) => ref
      .watch(organizationTeamProvider(active.organizationId))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorState(
          error: error,
          onRetry: () =>
              ref.invalidate(organizationTeamProvider(active.organizationId)),
        ),
        data: (team) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('Team', 'Equipo', 'Équipe'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final member in team.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(member.name.isEmpty ? member.email : member.name),
                subtitle: Text(
                  member.status == 'revoked'
                      ? _t('Access removed', 'Acceso retirado', 'Accès retiré')
                      : member.roles
                            .map(
                              (key) => OrganizationRole.values
                                  .firstWhere((r) => r.key == key)
                                  .label(
                                    isSpanish(context),
                                    french: isFrench(context),
                                  ),
                            )
                            .join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(active, member: member),
              ),
            if (team.invitations.any(
              (invite) => invite.activeAt(DateTime.now()),
            )) ...[
              const SizedBox(height: 24),
              Text(
                _t(
                  'Open invitations',
                  'Invitaciones pendientes',
                  'Invitations en cours',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final invite in team.invitations.where(
                (i) => i.activeAt(DateTime.now()),
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    invite.contact ??
                        _t(
                          'Invitation code',
                          'Código de invitación',
                          'Code d’invitation',
                        ),
                  ),
                  subtitle: Text(
                    _t(
                      'Expires ${MaterialLocalizations.of(context).formatShortDate(invite.expiresAt.toLocal())}',
                      'Vence ${MaterialLocalizations.of(context).formatShortDate(invite.expiresAt.toLocal())}',
                      'Expire le ${MaterialLocalizations.of(context).formatShortDate(invite.expiresAt.toLocal())}',
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await ref
                                  .read(membershipRepositoryProvider)
                                  .revokeInvite(invite.id);
                              ref.invalidate(
                                organizationTeamProvider(active.organizationId),
                              );
                            } catch (error) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      membershipError(context, error),
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    child: Text(_t('Revoke', 'Revocar', 'Révoquer')),
                  ),
                ),
            ],
          ],
        ),
      );
}

class MembershipEditor extends ConsumerStatefulWidget {
  const MembershipEditor({super.key, required this.organization, this.member});
  final OrganizationMembership organization;
  final TeamMember? member;
  @override
  ConsumerState<MembershipEditor> createState() => _MembershipEditorState();
}

class _MembershipEditorState extends ConsumerState<MembershipEditor> {
  late Set<String> _roles;
  late Set<String> _permissions;
  final _contact = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _createdCode;
  DateTime? _expires;
  bool get _owner => widget.organization.roles.contains('company_owner');
  String _t(String en, String es, [String? fr]) =>
      localizedText(context, en, es, fr ?? en);
  @override
  void initState() {
    super.initState();
    _roles = widget.member?.roles.toSet() ?? {'operator'};
    _permissions = widget.member?.permissions.toSet() ?? {};
  }

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<void> _save({bool revoke = false}) async {
    if (_busy || _roles.isEmpty) return;
    if (!await requireOnlineAction(context, ref) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(membershipRepositoryProvider);
      final member = widget.member;
      if (member == null) {
        final invitation = await repository.invite(
          widget.organization.organizationId,
          _roles.toList(),
          _permissions.toList(),
          _contact.text,
        );
        if (mounted) {
          setState(() {
            _createdCode = invitation['code'] as String;
            _expires = DateTime.parse(invitation['expires_at'] as String);
          });
        }
      } else {
        await repository.updateMember(
          widget.organization.organizationId,
          member.profileId,
          _roles.toList(),
          _permissions.toList(),
          revoke ? 'revoked' : 'active',
        );
        if (mounted) {
          await refreshMembership(ref);
        }
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) setState(() => _error = membershipError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _createdCode!));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('Invitation copied', 'Invitación copiada', 'Invitation copiée'),
          ),
        ),
      );
    }
  }

  Future<void> _share() async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: _t(
            'Join ${widget.organization.name} in Vortice Next. Sign in with your email or phone, choose Use invitation, and enter: $_createdCode',
            'Únete a ${widget.organization.name} en Vortice Next. Accede con tu correo o teléfono, elige Usar invitación e introduce: $_createdCode',
            'Rejoignez ${widget.organization.name} sur Vortice Next. Connectez-vous avec votre adresse courriel ou votre téléphone, choisissez « Utiliser une invitation », puis saisissez : $_createdCode',
          ),
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(context, error));
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _createdCode != null
                      ? _t(
                          'Invitation ready',
                          'Invitación lista',
                          'Invitation prête',
                        )
                      : widget.member == null
                      ? _t(
                          'Invite teammate',
                          'Invitar a una persona',
                          'Inviter un membre de l’équipe',
                        )
                      : widget.member!.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: _t('Close', 'Cerrar', 'Fermer'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_createdCode != null) ...[
            Text(
              _t(
                'Share this code with your teammate. It can be used once.',
                'Comparte este código con la persona invitada. Solo se puede usar una vez.',
                'Partagez ce code avec le membre de votre équipe. Il ne peut être utilisé qu’une fois.',
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              _createdCode!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Expires ${MaterialLocalizations.of(context).formatShortDate(_expires!.toLocal())}',
                'Vence ${MaterialLocalizations.of(context).formatShortDate(_expires!.toLocal())}',
                'Expire le ${MaterialLocalizations.of(context).formatShortDate(_expires!.toLocal())}',
              ),
            ),
            const SizedBox(height: 20),
            const OnlineOnlyNotice(),
            FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
              label: Text(
                _t(
                  'Share invitation',
                  'Compartir invitación',
                  'Partager l’invitation',
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined),
              label: Text(_t('Copy code', 'Copiar código', 'Copier le code')),
            ),
          ] else ...[
            Text(
              _t('Working roles', 'Roles de trabajo', 'Rôles de travail'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Choose every role this person performs.',
                'Elige todos los roles que desempeña esta persona.',
                'Choisissez tous les rôles exercés par cette personne.',
              ),
            ),
            for (final role in OrganizationRole.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  role.label(isSpanish(context), french: isFrench(context)),
                ),
                value: _roles.contains(role.key),
                onChanged:
                    _busy ||
                        (!_owner &&
                            (role == OrganizationRole.companyOwner ||
                                widget.member?.isOwner == true))
                    ? null
                    : (checked) => setState(() {
                        if (checked == true) {
                          _roles.add(role.key);
                        } else {
                          _roles.remove(role.key);
                        }
                      }),
              ),
            const SizedBox(height: 12),
            Text(
              _t(
                'Delegated permissions',
                'Permisos delegados',
                'Autorisations déléguées',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Supervisors manage daily work. Team access, billing and inspection administration are delegated separately.',
                'Los supervisores gestionan el trabajo diario. El equipo, la facturación y las inspecciones requieren permisos separados.',
                'Les superviseurs organisent le travail quotidien. La gestion de l’équipe, la facturation et l’administration des inspections nécessitent des autorisations distinctes.',
              ),
            ),
            if (_roles.contains('company_owner'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _t(
                    'Company Owners already have every organization permission.',
                    'Los propietarios ya tienen todos los permisos de la empresa.',
                    'Les propriétaires de l’entreprise disposent déjà de toutes les autorisations de l’organisation.',
                  ),
                ),
              )
            else
              for (final permission in OrganizationPermission.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    permission.label(
                      isSpanish(context),
                      french: isFrench(context),
                    ),
                  ),
                  value: _permissions.contains(permission.key),
                  onChanged: !_owner || _busy
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            _permissions.add(permission.key);
                          } else {
                            _permissions.remove(permission.key);
                          }
                        }),
                ),
            if (widget.member == null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextField(
                  controller: _contact,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Restrict to email or phone (optional)',
                      'Limitar a correo o teléfono (opcional)',
                    ),
                    helperText: _t(
                      'The person must verify this contact before joining.',
                      'La persona debe verificar este contacto antes de unirse.',
                    ),
                  ),
                ),
              ),
            if (_roles.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _t('Choose at least one role.', 'Elige al menos un rol.'),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy || _roles.isEmpty ? null : () => _save(),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.member == null
                          ? _t('Create invitation', 'Crear invitación')
                          : widget.member!.status == 'revoked'
                          ? _t('Restore access', 'Restaurar acceso')
                          : _t('Save access', 'Guardar acceso'),
                    ),
            ),
            if (widget.member != null && widget.member!.status == 'active')
              TextButton(
                onPressed: _busy ? null : () => _save(revoke: true),
                child: Text(
                  _t('Remove company access', 'Retirar acceso a la empresa'),
                ),
              ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}
