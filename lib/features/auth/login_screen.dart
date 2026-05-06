import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

// ── Dev mode flag — set to false before shipping ───────────────────────────
const bool kDevMode = false;

// Test account credentials (dev only)
const _devAccounts = [
  {
    'label': '1 · Owner',
    'email': 'owner@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFF1A6B3C
  },
  {
    'label': '2 · Tech',
    'email': 'tech@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFF1565C0
  },
  {
    'label': '3 · Client (Managed)',
    'email': 'client@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFF6A1B9A
  },
  {
    'label': '4 · Operator',
    'email': 'operator@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFFE65100
  },
  {
    'label': '5 · Planning Tier',
    'email': 'client_planning@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFF00838F
  },
  {
    'label': '6 · Paradise Marina',
    'email': 'paradise@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFF004527
  },
  {
    'label': '7 · Client Mechanic',
    'email': 'client_mechanic@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFF4527A0
  },
  {
    'label': '8 · Operator (org)',
    'email': 'client_operator@vortice.dev',
    'password': '<REDACTED_TEST_PASSWORD>',
    'color': 0xFFBF360C
  },
];

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
  void _handleLogoTap() {
    // One tap opens the dev login panel for local debug builds.
    _showDevPanel();
  }

  void _showDevPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Dev Login',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _devAccounts.length,
                  itemBuilder: (context, index) {
                    final acct = _devAccounts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Color(acct['color'] as int).withValues(alpha: 0.15),
                        child: Text(
                          (acct['label'] as String).split('·').first.trim(),
                          style: TextStyle(
                              color: Color(acct['color'] as int),
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(acct['label'] as String,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: Text(acct['email'] as String,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _emailCtrl.text = acct['email'] as String;
                        _passwordCtrl.text = acct['password'] as String;
                        _submit();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authControllerProvider.notifier)
        .signIn(_emailCtrl.text.trim(), _passwordCtrl.text);

    final authState = ref.read(authControllerProvider);
    if (authState.hasError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authState.error.toString()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  List<Widget> _buildDevButtons() {
    return [
      const Divider(height: 32),
      Center(
        child: Text(
          'DEV — Quick Login',
          style: TextStyle(
              fontSize: 11, color: Colors.grey.shade500, letterSpacing: 1.2),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _devAccounts.map((acct) {
          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(acct['color'] as int),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              minimumSize: Size.zero,
            ),
            onPressed: ref.read(authControllerProvider).isLoading
                ? null
                : () async {
                    await ref.read(authControllerProvider.notifier).signIn(
                        acct['email'] as String, acct['password'] as String);
                    final authState = ref.read(authControllerProvider);
                    if (!mounted) return;
                    if (authState.hasError) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(authState.error.toString()),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
            child: Text(acct['label'] as String),
          );
        }).toList(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      body: SafeArea(
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
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Center(
                                  child: Icon(Icons.engineering,
                                      size: 48, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Vórtice Mechanical',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.loginSubtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
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
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return l10n.fieldRequired;
                        if (v.length < 6) return l10n.passwordTooShort;
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        child: Text(l10n.forgotPassword),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.signIn),
                    ),
                    const SizedBox(height: 16),
                    // ── Dev login buttons ──────────────────────────────────
                    if (kDevMode) ..._buildDevButtons(),
                    const SizedBox(height: 16),
                    // Language toggle
                    Center(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final locale = ref.watch(localeProvider);
                          final isEn = locale.languageCode == 'en';
                          return TextButton.icon(
                            icon: const Icon(Icons.language, size: 16),
                            label: Text(isEn ? 'Español' : 'English'),
                            onPressed: () => ref
                                .read(localeProvider.notifier)
                                .setLocale(Locale(isEn ? 'es' : 'en')),
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
    );
  }
}
