import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'company_purpose.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/membership/membership_provider.dart';
import 'package:vortice_app/features/membership/membership_feedback.dart';

class OrganizationOnboardingScreen extends ConsumerStatefulWidget {
  const OrganizationOnboardingScreen({super.key, this.joinOnly = false});
  final bool joinOnly;
  @override
  ConsumerState<OrganizationOnboardingScreen> createState() =>
      _OrganizationOnboardingScreenState();
}

class _OrganizationOnboardingScreenState
    extends ConsumerState<OrganizationOnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _invitation = TextEditingController();
  bool _join = false;
  bool _busy = false;
  CompanyPurpose? _purpose;
  final _operation = const Uuid().v4();
  String? _error;
  String _t(String en, String es, [String? fr]) =>
      localizedText(context, en, es, fr ?? en);
  @override
  void initState() {
    super.initState();
    _join = widget.joinOnly;
    _name.text = ref.read(profileProvider).valueOrNull?.fullName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _invitation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_join && _purpose == null) {
      setState(
        () => _error = _t(
          'Choose how your company will use the app.',
          'Elige cómo usará tu empresa la aplicación.',
          'Choisissez comment votre entreprise utilisera l’application.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(membershipRepositoryProvider);
      if (_join) {
        await repository.redeem(_invitation.text, _name.text);
      } else {
        await repository.createCompanyWithPurpose(
          _company.text,
          _name.text,
          _purpose!,
          _operation,
        );
      }
      if (!mounted) return;
      await refreshMembership(ref);
      if (mounted) context.go('/client/dashboard');
    } catch (error) {
      if (mounted) setState(() => _error = membershipError(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_t('Your company', 'Tu empresa', 'Votre entreprise')),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => ref.read(authControllerProvider.notifier).signOut(),
          child: Text(_t('Sign out', 'Cerrar sesión', 'Se déconnecter')),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _t(
                      'Where do you work?',
                      '¿Dónde trabajas?',
                      'Où travaillez-vous ?',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _join
                        ? _t(
                            'Join with the roles and permissions selected by your company.',
                            'Únete con los roles y permisos elegidos por tu empresa.',
                            'Rejoignez l’espace avec les rôles et autorisations choisis par votre entreprise.',
                          )
                        : _t(
                            'Create your company workspace. You will be its Company Owner.',
                            'Crea el espacio de tu empresa. Serás su propietario.',
                            'Créez l’espace de travail de votre entreprise. Vous en serez le propriétaire.',
                          ),
                  ),
                  const SizedBox(height: 24),
                  if (!widget.joinOnly) ...[
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                            _t(
                              'Create company',
                              'Crear empresa',
                              'Créer une entreprise',
                            ),
                          ),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                            _t(
                              'Use invitation',
                              'Usar invitación',
                              'Utiliser une invitation',
                            ),
                          ),
                        ),
                      ],
                      selected: {_join},
                      onSelectionChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _join = value.single;
                              _error = null;
                            }),
                    ),
                    const SizedBox(height: 24),
                  ],
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: _t('Your name', 'Tu nombre', 'Votre nom'),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? _t(
                            'Enter your name.',
                            'Escribe tu nombre.',
                            'Saisissez votre nom.',
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (_join)
                    TextFormField(
                      controller: _invitation,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Invitation code',
                          'Código de invitación',
                          'Code d’invitation',
                        ),
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? _t(
                              'Enter your invitation code.',
                              'Escribe el código de invitación.',
                              'Saisissez votre code d’invitation.',
                            )
                          : null,
                    )
                  else
                    TextFormField(
                      controller: _company,
                      enabled: !_busy,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Company name',
                          'Nombre de empresa',
                          'Nom de l’entreprise',
                        ),
                      ),
                      validator: (value) => (value ?? '').trim().length < 2
                          ? _t(
                              'Enter your company name.',
                              'Escribe el nombre de tu empresa.',
                              'Saisissez le nom de votre entreprise.',
                            )
                          : null,
                    ),
                  if (!_join) ...[
                    const SizedBox(height: 24),
                    CompanyPurposePicker(
                      value: _purpose,
                      spanish: isSpanish(context),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _purpose = value;
                              _error = null;
                            }),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _join
                                ? _t(
                                    'Join company',
                                    'Unirme a la empresa',
                                    'Rejoindre l’entreprise',
                                  )
                                : _t(
                                    'Create company',
                                    'Crear empresa',
                                    'Créer une entreprise',
                                  ),
                          ),
                  ),
                  if (_join)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _t(
                          'An expired or revoked invitation needs a new code from your company administrator.',
                          'Si la invitación ha vencido o fue revocada, pide otro código al administrador de tu empresa.',
                          'Une invitation expirée ou révoquée doit être remplacée par un nouveau code fourni par l’administrateur de votre entreprise.',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
