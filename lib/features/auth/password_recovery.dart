import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';

const recoveryRedirect = 'com.vortice.next://auth/recovery';
bool isRecoveryCallback(Uri uri) =>
    uri.scheme == 'com.vortice.next' &&
    uri.host == 'auth' &&
    uri.path == '/recovery';
String? validateRecoveryPassword(
  String password,
  String confirmation,
  bool es,
) {
  if (password.length < 8) {
    return es ? 'Usa al menos 8 caracteres.' : 'Use at least 8 characters.';
  }
  if (password != confirmation) {
    return es ? 'Las contraseñas no coinciden.' : 'Passwords do not match.';
  }
  return null;
}

enum RecoveryPhase { idle, verifying, ready, failed }

final passwordRecoveryProvider =
    ChangeNotifierProvider<PasswordRecoveryController>(
      (_) => PasswordRecoveryController(),
    );

class PasswordRecoveryController extends ChangeNotifier {
  RecoveryPhase phase = RecoveryPhase.idle;
  String? _account;
  StreamSubscription<Uri>? _links;
  StreamSubscription<AuthState>? _auth;
  bool _disposed = false;
  String? _lastLink;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _account = prefs.getString('password_recovery_account');
    if (_account != null && supabase.auth.currentUser?.id == _account) {
      phase = RecoveryPhase.ready;
    }
    _auth = supabase.auth.onAuthStateChange.listen((event) {
      if (phase != RecoveryPhase.verifying &&
          _account != null &&
          event.session?.user.id != _account) {
        _account = null;
        phase = RecoveryPhase.idle;
        unawaited(prefs.remove('password_recovery_account'));
        _notify();
      }
    });
    final links = AppLinks();
    _links = links.uriLinkStream.listen(
      (uri) => unawaited(handleCallback(uri)),
      onError: (_) {
        phase = RecoveryPhase.failed;
        _notify();
      },
    );
    final initial = await links.getInitialLink();
    if (initial != null) await handleCallback(initial);
  }

  Future<void> request(String email) => supabase.auth.resetPasswordForEmail(
    email.trim(),
    redirectTo: recoveryRedirect,
  );
  Future<void> handleCallback(Uri uri) async {
    if (!isRecoveryCallback(uri) || _lastLink == uri.toString()) return;
    _lastLink = uri.toString();
    phase = RecoveryPhase.verifying;
    _notify();
    try {
      final response = await supabase.auth
          .getSessionFromUrl(uri)
          .timeout(const Duration(seconds: 20));
      if (response.redirectType != 'passwordRecovery') {
        throw const AuthException('Not a recovery link');
      }
      _account = response.session.user.id;
      await (await SharedPreferences.getInstance()).setString(
        'password_recovery_account',
        _account!,
      );
      phase = RecoveryPhase.ready;
    } catch (_) {
      phase = RecoveryPhase.failed;
    }
    _notify();
  }

  Future<void> updatePassword(String password) async {
    if (phase != RecoveryPhase.ready ||
        _account == null ||
        supabase.auth.currentUser?.id != _account) {
      phase = RecoveryPhase.failed;
      _notify();
      throw const AuthException('Recovery session expired');
    }
    await supabase.auth.updateUser(UserAttributes(password: password));
    await (await SharedPreferences.getInstance()).remove(
      'password_recovery_account',
    );
    _account = null;
    phase = RecoveryPhase.idle;
    _notify();
    await supabase.auth.signOut(scope: SignOutScope.local);
  }

  void dismiss() {
    phase = RecoveryPhase.idle;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _links?.cancel();
    _auth?.cancel();
    super.dispose();
  }
}

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key, this.reset = false});
  final bool reset;
  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false, _sent = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final es = isSpanish(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(passwordRecoveryProvider);
      if (widget.reset) {
        await controller.updatePassword(_password.text);
        if (mounted) {
          context.go('/login');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                es
                    ? 'Contraseña actualizada. Inicia sesión.'
                    : 'Password updated. Sign in with your new password.',
              ),
            ),
          );
        }
      } else {
        await controller.request(_email.text);
        if (mounted) setState(() => _sent = true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = es
              ? 'No se pudo completar. Revisa la conexión o solicita un enlace nuevo.'
              : 'Could not complete this step. Check your connection or request a new link.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final es = isSpanish(context),
        controller = ref.watch(passwordRecoveryProvider);
    final valid = !widget.reset || controller.phase == RecoveryPhase.ready;
    return Scaffold(
      appBar: AppBar(title: Text(es ? 'Recuperar acceso' : 'Recover access')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                if (widget.reset && controller.phase == RecoveryPhase.verifying)
                  const LinearProgressIndicator()
                else if (!valid) ...[
                  Text(
                    es
                        ? 'Este enlace venció, ya se usó o se abrió en otro dispositivo. Solicita uno nuevo desde esta app.'
                        : 'This link expired, was already used, or was opened on another device. Request a new link from this app.',
                  ),
                  TextButton(
                    onPressed: () {
                      controller.dismiss();
                      context.go('/forgot-password');
                    },
                    child: Text(es ? 'Solicitar enlace' : 'Request a new link'),
                  ),
                ] else if (_sent) ...[
                  Text(
                    es
                        ? 'Si existe una cuenta con ese correo, recibirás un enlace. Ábrelo en este dispositivo para elegir una contraseña nueva. Revisa también el correo no deseado.'
                        : 'If an account uses that email, you will receive a link. Open it on this device to choose a new password. Check your spam folder too.',
                  ),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(
                      es ? 'Volver al inicio de sesión' : 'Back to sign in',
                    ),
                  ),
                ] else ...[
                  if (!widget.reset)
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: es ? 'Correo electrónico' : 'Email address',
                      ),
                      validator: (value) =>
                          RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : es
                          ? 'Ingresa un correo válido.'
                          : 'Enter a valid email address.',
                    )
                  else ...[
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: es ? 'Nueva contraseña' : 'New password',
                      ),
                      validator: (_) => validateRecoveryPassword(
                        _password.text,
                        _password.text,
                        es,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmation,
                      enabled: !_busy,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: es
                            ? 'Confirmar contraseña'
                            : 'Confirm password',
                      ),
                      validator: (_) => validateRecoveryPassword(
                        _password.text,
                        _confirmation.text,
                        es,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? (es ? 'Espera…' : 'Please wait…')
                          : widget.reset
                          ? (es ? 'Guardar contraseña' : 'Save password')
                          : (es ? 'Enviar enlace' : 'Send recovery link'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
