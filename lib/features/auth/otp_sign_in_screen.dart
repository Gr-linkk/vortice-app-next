import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/otp_auth_provider.dart';

class OtpSignInScreen extends ConsumerStatefulWidget {
  const OtpSignInScreen({super.key});
  @override
  ConsumerState<OtpSignInScreen> createState() => _OtpSignInScreenState();
}

class _OtpSignInScreenState extends ConsumerState<OtpSignInScreen> {
  final _contact = TextEditingController();
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  VerificationChannel _channel = VerificationChannel.email;
  OtpContact? _sentTo;
  bool _busy = false;
  int _resendSeconds = 0;
  Timer? _timer;
  String? _error;
  bool get _es => isSpanish(context);
  String _t(String en, String es) => _es ? es : en;

  @override
  void dispose() {
    _contact.dispose();
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String _failure(Object error) {
    if (error is AuthException) {
      if (const {
        'otp_expired',
        'otp_disabled',
        'invalid_credentials',
      }.contains(error.code)) {
        return _t(
          'That code is invalid or expired. Check it or request a new code.',
          'El código no es válido o ha vencido. Revísalo o solicita otro.',
        );
      }
      if (const {
        'over_email_send_rate_limit',
        'over_sms_send_rate_limit',
        'over_request_rate_limit',
      }.contains(error.code)) {
        return _t(
          'Please wait before requesting another code.',
          'Espera antes de solicitar otro código.',
        );
      }
      if (error.code == 'sms_send_failed' ||
          error.code == 'phone_provider_disabled') {
        return _t(
          'Text messages are unavailable. Use email or try again later.',
          'Los mensajes de texto no están disponibles. Usa el correo o inténtalo más tarde.',
        );
      }
    }
    return _t(
      'We could not verify your sign-in. Check your connection and try again.',
      'No pudimos verificar tu acceso. Revisa tu conexión e inténtalo de nuevo.',
    );
  }

  Future<void> _send() async {
    if (_busy || _resendSeconds > 0) return;
    if (!ref.read(otpDeliveryChannelsProvider).contains(_sentTo?.channel ?? _channel)) return;
    if (_sentTo == null && !_form.currentState!.validate()) return;
    final contact = _sentTo ?? OtpContact.parse(_channel, _contact.text)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(otpAuthRepositoryProvider)
          .send(contact, language: _es ? 'es' : 'en');
      if (!mounted) return;
      setState(() {
        _sentTo = contact;
        _resendSeconds = 60;
        _code.clear();
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _resendSeconds--);
        if (_resendSeconds <= 0) timer.cancel();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(otpAuthRepositoryProvider).verify(_sentTo!, _code.text);
      // Auth/router chooses onboarding or the returning user's dashboard.
    } catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(otpDeliveryChannelsProvider);
    if (channels.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_t('Sign in with a code', 'Acceder con un código'))),
        body: Padding(padding: const EdgeInsets.all(24), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_t('Code sign-in is not available yet. Use your email and password to continue.',
              'El acceso con código aún no está disponible. Usa tu correo y contraseña para continuar.')),
            const SizedBox(height:24),
            FilledButton(onPressed: () => Navigator.maybePop(context), child: Text(_t('Back to sign in', 'Volver al acceso'))),
          ],
        )),
      );
    }
    if (!channels.contains(_channel) && _sentTo == null) _channel = channels.first;
    return Scaffold(
    appBar: AppBar(
      title: Text(_t('Sign in with a code', 'Acceder con un código')),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _sentTo == null
                        ? _t('Your work starts here', 'Tu trabajo empieza aquí')
                        : _t('Check your messages', 'Revisa tus mensajes'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _sentTo == null
                        ? _t(
                            'Enter your email or phone number. We will send a verification code.',
                            'Escribe tu correo o teléfono. Te enviaremos un código de verificación.',
                          )
                        : _t(
                            'Enter the code sent to ${_sentTo!.value}.',
                            'Escribe el código enviado a ${_sentTo!.value}.',
                          ),
                  ),
                  const SizedBox(height: 24),
                  if (_sentTo == null) ...[
                    SegmentedButton<VerificationChannel>(
                      segments: [
                        ButtonSegment(
                          value: VerificationChannel.email,
                          enabled: channels.contains(VerificationChannel.email),
                          label: Text(_t('Email', 'Correo')),
                          icon: const Icon(Icons.email_outlined),
                        ),
                        ButtonSegment(
                          value: VerificationChannel.phone,
                          enabled: channels.contains(VerificationChannel.phone),
                          label: Text(_t('Phone', 'Teléfono')),
                          icon: const Icon(Icons.phone_outlined),
                        ),
                      ],
                      selected: {_channel},
                      onSelectionChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _channel = value.single;
                              _contact.clear();
                              _error = null;
                            }),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      key: ValueKey(_channel),
                      controller: _contact,
                      enabled: !_busy,
                      keyboardType: _channel == VerificationChannel.email
                          ? TextInputType.emailAddress
                          : TextInputType.phone,
                      autofillHints: _channel == VerificationChannel.email
                          ? const [AutofillHints.email]
                          : const [AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        labelText: _channel == VerificationChannel.email
                            ? _t('Email', 'Correo')
                            : _t(
                                'Phone with country code',
                                'Teléfono con código de país',
                              ),
                        hintText: _channel == VerificationChannel.phone
                            ? '+1 555 123 4567'
                            : null,
                      ),
                      validator: (value) =>
                          OtpContact.parse(_channel, value ?? '') == null
                          ? (_channel == VerificationChannel.email
                                ? _t(
                                    'Enter a valid email.',
                                    'Escribe un correo válido.',
                                  )
                                : _t(
                                    'Include + and your country code.',
                                    'Incluye + y el código de país.',
                                  ))
                          : null,
                    ),
                  ] else ...[
                    TextFormField(
                      key: const ValueKey('verification-code'),
                      controller: _code,
                      enabled: !_busy,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: InputDecoration(
                        labelText: _t(
                          'Verification code',
                          'Código de verificación',
                        ),
                      ),
                      onFieldSubmitted: (_) => _verify(),
                      validator: (value) => (value ?? '').length < 6
                          ? _t(
                              'Enter the complete code.',
                              'Escribe el código completo.',
                            )
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _timer?.cancel();
                                setState(() {
                                  _sentTo = null;
                                  _resendSeconds = 0;
                                  _code.clear();
                                  _error = null;
                                });
                              },
                        child: Text(
                          _t(
                            'Change email or phone',
                            'Cambiar correo o teléfono',
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        key: const ValueKey('verification-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : (_sentTo == null ? _send : _verify),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _sentTo == null
                                ? _t('Send code', 'Enviar código')
                                : _t(
                                    'Verify and continue',
                                    'Verificar y continuar',
                                  ),
                          ),
                  ),
                  if (_sentTo != null)
                    TextButton(
                      onPressed: _busy || _resendSeconds > 0 ? null : _send,
                      child: Text(
                        _resendSeconds > 0
                            ? _t(
                                'Resend in ${_resendSeconds}s',
                                'Reenviar en ${_resendSeconds}s',
                              )
                            : _t('Send a new code', 'Enviar otro código'),
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
}
