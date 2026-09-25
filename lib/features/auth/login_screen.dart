import 'package:vortice_app/core/localized_text.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/auth/dev_login_switch.dart';
import 'package:vortice_app/core/language_picker.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _signingIn = false;

  bool get _devAvailable => ref.read(devLoginAvailableProvider);

  void _handleLogoTap() {
    if (_devAvailable &&
        !_signingIn &&
        !ref.read(authControllerProvider).isLoading) {
      showDevAccountPicker(context, ref);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (ref.read(devAccountSwitchProvider).loading) return;
    ref.read(devAccountSwitchProvider.notifier).clearError();
    await _signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
  }

  Future<void> _signIn(String email, String password) async {
    if (_signingIn ||
        ref.read(authControllerProvider).isLoading ||
        ref.read(devAccountSwitchProvider).loading) {
      return;
    }
    setState(() => _signingIn = true);
    try {
      await ref.read(authControllerProvider.notifier).signIn(email, password);
      if (!mounted) return;
      final state = ref.read(authControllerProvider);
      if (state.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(context, state.error))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(context, error))));
      }
    } finally {
      if (mounted) {
        setState(() => _signingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading =
        _signingIn ||
        ref.watch(authControllerProvider).isLoading ||
        ref.watch(devAccountSwitchProvider).loading;
    final devAvailable = ref.watch(devLoginAvailableProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 64),
                  // Brand
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _handleLogoTap,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: context.appColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Center(
                                    child: Icon(
                                      Icons.engineering,
                                      size: 48,
                                      color: context.appColors.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Vórtice Mechanical',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.loginSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: context.appColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('code-sign-in'),
                          onPressed: isLoading
                              ? null
                              : () => context.push('/verify'),
                          icon: const Icon(Icons.mark_email_read_outlined),
                          label: Text(
                            localizedText(
                              context,
                              'Continue with email or phone',
                              'Acceder con correo o teléfono',
                              'Continuer avec un courriel ou un téléphone',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          localizedText(
                            context,
                            'Or use your existing password',
                            'O usa tu contraseña actual',
                            'Ou utilisez votre mot de passe actuel',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l10n.email,
                            prefixIcon: const Icon(Icons.email_outlined),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return l10n.fieldRequired;
                            }
                            if (!v.contains('@')) return l10n.invalidEmail;
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: l10n.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.fieldRequired;
                            }
                            if (v.length < 6) return l10n.passwordTooShort;
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => context.push('/forgot-password'),
                            child: Text(l10n.forgotPassword),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: isLoading ? null : _submit,
                          child: isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.appColors.onPrimary,
                                  ),
                                )
                              : Text(l10n.signIn),
                        ),
                        const SizedBox(height: 16),
                        // Language toggle
                        if (devAvailable) ...[
                          OutlinedButton.icon(
                            key: const ValueKey('dev-sign-in'),
                            onPressed: isLoading
                                ? null
                                : () => showDevAccountPicker(context, ref),
                            icon: const Icon(Icons.switch_account_outlined),
                            label: Text(
                              localizedText(
                                context,
                                'Developer sign-in',
                                'Acceso de desarrollo',
                                'Connexion de développement',
                              ),
                            ),
                          ),
                          const DevAccountSwitchNotice(),
                        ],
                        Center(
                          child: Consumer(
                            builder: (context, ref, _) {
                              final locale = ref.watch(localeProvider);
                              return TextButton.icon(
                                icon: const Icon(Icons.language, size: 16),
                                label: Text(languageName(locale)),
                                onPressed: () =>
                                    showLanguagePicker(context, ref),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
