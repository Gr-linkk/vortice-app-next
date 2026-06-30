import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/l10n/app_localizations.dart';
import 'package:vortice_app/core/theme.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

// ── Dev login panel — debug builds only ──────────────────────────────────────
const bool kDevMode = kDebugMode;

class _DevAccount {
  final String group;
  final String label;
  final String subtitle;
  final List<String> workflows;
  final String email;
  final String password;
  final int color;

  const _DevAccount({
    required this.group,
    required this.label,
    required this.subtitle,
    required this.workflows,
    required this.email,
    required this.password,
    required this.color,
  });
}

const _devAccounts = [
  _DevAccount(
    group: 'Vórtice team',
    label: 'Vórtice Owner/Admin',
    subtitle:
        'Service business owner view for clients, assets, work, and billing.',
    workflows: ['Clients', 'Assets', 'Work orders', 'Billing'],
    email: 'owner@vortice.dev',
    password: '<REDACTED_TEST_PASSWORD>',
    color: 0xFF1A6B3C,
  ),
  _DevAccount(
    group: 'Vórtice team',
    label: 'Vórtice Tech/Mechanic',
    subtitle: 'Internal mechanic view for assigned work and service reporting.',
    workflows: ['Assigned work', 'Service reports', 'PM follow-up'],
    email: 'tech@vortice.dev',
    password: '<REDACTED_TEST_PASSWORD>',
    color: 0xFF1565C0,
  ),
  _DevAccount(
    group: 'Simulated client admins',
    label: 'Client 1 Admin',
    subtitle:
        'Generic client admin with team, vessel, and checklist workflows.',
    workflows: ['Team', 'Assets', 'Operator checks'],
    email: 'paradise@vortice.dev',
    password: '<REDACTED_TEST_PASSWORD>',
    color: 0xFF004527,
  ),
  _DevAccount(
    group: 'Simulated client admins',
    label: 'Client 2 Admin',
    subtitle: 'Second generic client admin for cross-client workflow testing.',
    workflows: ['Team', 'Assets', 'PM planning'],
    email: 'client@vortice.dev',
    password: '<REDACTED_TEST_PASSWORD>',
    color: 0xFF6A1B9A,
  ),
  _DevAccount(
    group: 'Client field team',
    label: 'Client Mechanic',
    subtitle: 'Client-side mechanic view for PM checklists and asset history.',
    workflows: ['Mechanic checks', 'Asset history', 'PM parts'],
    email: 'client_mechanic@vortice.dev',
    password: '<REDACTED_TEST_PASSWORD>',
    color: 0xFF4527A0,
  ),
  _DevAccount(
    group: 'Client field team',
    label: 'Operator/Captain',
    subtitle: 'Captain/operator view for vessel pre-op and daily checklists.',
    workflows: ['Pre-op', 'Daily checks', 'Maintenance flags'],
    email: 'operator@vortice.dev',
    password: '<REDACTED_TEST_PASSWORD>',
    color: 0xFFE65100,
  ),
];

class _DevWorkflowChip extends StatelessWidget {
  final String label;
  final Color color;

  const _DevWorkflowChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

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
    if (!kDevMode) return;
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
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Dev Persona Switchboard',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Pick a tester persona. Capability chips are static hints for now.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: _buildDevAccountTiles(ctx),
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

  List<Widget> _buildDevAccountTiles(BuildContext sheetContext) {
    final widgets = <Widget>[];
    String? currentGroup;

    for (final acct in _devAccounts) {
      if (acct.group != currentGroup) {
        currentGroup = acct.group;
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              currentGroup.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
        );
      }

      widgets.add(
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(acct.color).withValues(alpha: 0.15),
            child: Text(
              acct.label.characters.first.toUpperCase(),
              style: TextStyle(
                color: Color(acct.color),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            acct.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acct.subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final workflow in acct.workflows)
                      _DevWorkflowChip(
                        label: workflow,
                        color: Color(acct.color),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  acct.email,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            _emailCtrl.text = acct.email;
            _passwordCtrl.text = acct.password;
            _submit();
          },
        ),
      );
    }

    return widgets;
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
