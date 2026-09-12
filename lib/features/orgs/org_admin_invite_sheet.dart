import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/clients/client_capability_provider.dart';
import 'package:vortice_app/features/org_codes/org_code_provider.dart';
import 'package:vortice_app/features/orgs/org_admin_support.dart';
import 'package:vortice_app/models/client_capability.dart';

class OrgAdminInviteSheet extends ConsumerStatefulWidget {
  final String orgId;
  final String ownerProfileId;

  const OrgAdminInviteSheet({
    super.key,
    required this.orgId,
    required this.ownerProfileId,
  });

  @override
  ConsumerState<OrgAdminInviteSheet> createState() =>
      _OrgAdminInviteSheetState();
}

class _OrgAdminInviteSheetState extends ConsumerState<OrgAdminInviteSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _selectedRole;
  String? _createdCode;
  String? _error;
  bool _submitting = false;
  bool _sharing = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _createInvite(
    ClientCapabilitySwitchboard switchboard,
    String role,
  ) async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    if (!switchboard.isEnabled(requiredCapabilityForInviteRole(role))) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final code = OrgCodeController.generateCode();
      final success = await ref
          .read(orgCodeControllerProvider.notifier)
          .createCode(
            code: code,
            intendedRole: role,
            maxUses: 1,
            singleUse: true,
            orgId: widget.orgId,
            notes:
                'Invite for ${_nameCtrl.text.trim()} (${_emailCtrl.text.trim()})',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
          );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (success) {
          _createdCode = code;
        } else {
          _error = friendlyError(
            context,
            ref.read(orgCodeControllerProvider).error,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyError(context, error);
      });
    }
  }

  Future<void> _copyCode(String code) async {
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSpanish(context) ? 'Código copiado' : 'Code copied'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(context, error));
    }
  }

  Future<void> _shareCode(BuildContext buttonContext, String code) async {
    if (_sharing) return;
    final es = isSpanish(context);
    final box = buttonContext.findRenderObject() as RenderBox?;
    setState(() => _sharing = true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: es
              ? 'Tu código de invitación es $code. Úsalo al registrarte en Vortice Next. Vence en 7 días y solo se puede usar una vez.'
              : 'Your invite code is $code. Use it when registering in Vortice Next. It expires in 7 days and can only be used once.',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(context, error));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context);
    final code = _createdCode;
    final capabilities = ref.watch(
      clientCapabilitiesProvider(widget.ownerProfileId),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: code != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    es ? 'Código de invitación creado' : 'Invite code created',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    es
                        ? 'No se envió ningún correo. Copia o comparte este código con la persona invitada para que se registre.'
                        : 'No email was sent. Copy or share this code with your team member so they can register.',
                  ),
                  const SizedBox(height: 20),
                  SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    es
                        ? 'Vence en 7 días. Un solo uso.'
                        : 'Expires in 7 days. Single use.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _copyCode(code),
                        icon: const Icon(Icons.copy),
                        label: Text(es ? 'Copiar' : 'Copy'),
                      ),
                      Builder(
                        builder: (buttonContext) => FilledButton.icon(
                          onPressed: _sharing
                              ? null
                              : () => _shareCode(buttonContext, code),
                          icon: const Icon(Icons.share_outlined),
                          label: Text(es ? 'Compartir' : 'Share'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(es ? 'Listo' : 'Done'),
                  ),
                ],
              )
            : capabilities.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(friendlyError(context, error)),
                    TextButton(
                      onPressed: () => ref.invalidate(
                        clientCapabilitiesProvider(widget.ownerProfileId),
                      ),
                      child: Text(es ? 'Intentar de nuevo' : 'Try again'),
                    ),
                  ],
                ),
                data: (switchboard) {
                  final mechanic = switchboard.isEnabled(
                    ClientCapability.pmChecklists,
                  );
                  final operator = switchboard.isEnabled(
                    ClientCapability.operationalChecklists,
                  );
                  final role =
                      _selectedRole ??
                      (mechanic ? 'client_mechanic' : 'client_operator');
                  final enabled = switchboard.isEnabled(
                    requiredCapabilityForInviteRole(role),
                  );
                  return Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          es ? 'Invitar a un miembro' : 'Invite team member',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          es
                              ? 'Crea un código y compártelo. No se envía ningún correo automáticamente.'
                              : 'Create a code, then share it. No email is sent automatically.',
                        ),
                        const SizedBox(height: 16),
                        Text(es ? 'Rol' : 'Role'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(es ? 'Mecánico' : 'Mechanic'),
                              selected: role == 'client_mechanic',
                              onSelected: mechanic && !_submitting
                                  ? (_) => setState(
                                      () => _selectedRole = 'client_mechanic',
                                    )
                                  : null,
                            ),
                            ChoiceChip(
                              label: Text(es ? 'Operador' : 'Operator'),
                              selected: role == 'client_operator',
                              onSelected: operator && !_submitting
                                  ? (_) => setState(
                                      () => _selectedRole = 'client_operator',
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        if (!mechanic)
                          Text(
                            es
                                ? 'Activa las listas de mantenimiento para invitar a mecánicos.'
                                : 'Enable PM / Mechanic Checklists to invite mechanics.',
                          ),
                        if (!operator)
                          Text(
                            es
                                ? 'Activa las listas operativas para invitar a operadores.'
                                : 'Enable Operational Checklists to invite operators.',
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameCtrl,
                          enabled: !_submitting,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: es ? 'Nombre' : 'Name',
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          validator: (value) => (value?.trim().isEmpty ?? true)
                              ? (es ? 'Escribe un nombre.' : 'Enter a name.')
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailCtrl,
                          enabled: !_submitting,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: es
                                ? 'Correo (opcional, como referencia)'
                                : 'Email (optional, for reference)',
                            prefixIcon: const Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            return email.isNotEmpty &&
                                    !RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(email)
                                ? (es
                                      ? 'Escribe un correo válido o deja el campo vacío.'
                                      : 'Enter a valid email or leave this blank.')
                                : null;
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _submitting || !enabled
                              ? null
                              : () => _createInvite(switchboard, role),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.key_outlined),
                          label: Text(
                            es
                                ? 'Crear código de invitación'
                                : 'Create invite code',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
