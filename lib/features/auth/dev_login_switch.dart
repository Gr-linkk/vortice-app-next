import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/orgs/org_provider.dart';
import 'dev_login_accounts.dart';
import 'dev_login_credentials.dart';

final devLoginAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(devLoginEnvironmentProvider) &&
      ref.watch(devLoginPasswordsProvider).isNotEmpty,
);

class DevAccountSwitchState {
  const DevAccountSwitchState({this.email, this.loading = false, this.error});
  final String? email;
  final bool loading;
  final Object? error;
}

/// Lives above routes so an error remains visible after sign-out opens Login.
/// Uses normal sign-out; account-owned drafts and queued work stay intact.
class DevAccountSwitchController extends StateNotifier<DevAccountSwitchState> {
  DevAccountSwitchController(this._ref) : super(const DevAccountSwitchState());
  final Ref _ref;

  void clearError() => state = const DevAccountSwitchState();

  Future<void> switchTo(String email) async {
    if (state.loading || !_ref.read(devLoginAvailableProvider)) {
      return;
    }
    final password = _ref.read(devLoginPasswordsProvider)[email];
    final session = _ref.read(sessionProvider);
    if (password == null || password.isEmpty || session?.user.email == email) {
      return;
    }
    final auth = _ref.read(authControllerProvider.notifier);
    if (_ref.read(authControllerProvider).isLoading) return;
    state = DevAccountSwitchState(email: email, loading: true);
    try {
      if (session != null) {
        await auth.signOut();
        if (!mounted) return;
        if (_ref.read(authControllerProvider).hasError) {
          state = DevAccountSwitchState(
            email: email,
            error: _ref.read(authControllerProvider).error,
          );
          return;
        }
      }
      await auth.signIn(email, password);
      if (!mounted) return;
      state = DevAccountSwitchState(
        email: email,
        error: _ref.read(authControllerProvider).error,
      );
    } catch (error) {
      if (mounted) {
        state = DevAccountSwitchState(email: email, error: error);
      }
    }
  }
}

final devAccountSwitchProvider =
    StateNotifierProvider<DevAccountSwitchController, DevAccountSwitchState>(
      (ref) => DevAccountSwitchController(ref),
    );

void showDevAccountPicker(BuildContext context, WidgetRef ref) {
  if (!ref.read(devLoginAvailableProvider) ||
      ref.read(devAccountSwitchProvider).loading ||
      ref.read(authControllerProvider).isLoading) {
    return;
  }
  final emails = ref.read(devLoginPasswordsProvider).keys.toSet();
  final current = ref.read(sessionProvider)?.user.email;
  final profile = ref.exists(profileProvider)
      ? ref.read(profileProvider).valueOrNull
      : null;
  final organization = ref.exists(currentUserOrgProvider)
      ? ref.read(currentUserOrgProvider).valueOrNull
      : null;
  final controller = ref.read(devAccountSwitchProvider.notifier);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DevLoginAccountSheet(
      configuredEmails: emails,
      currentEmail: current,
      currentCompany:
          profile?.email == current && organization?.id == profile?.orgId
          ? organization?.name
          : null,
      currentRoles: profile?.email == current
          ? profile?.organizationRoles ?? []
          : [],
      onSelected: (email) {
        Navigator.pop(sheetContext);
        controller.switchTo(email);
      },
    ),
  );
}

class DevAccountSwitchNotice extends ConsumerWidget {
  const DevAccountSwitchNotice({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(devLoginAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(devAccountSwitchProvider);
    if (status.error == null) return const SizedBox.shrink();
    final es = isSpanish(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            es
                ? 'No se pudo cambiar a ${status.email}.'
                : 'Could not switch to ${status.email}.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 4),
          Text(friendlyError(context, status.error)),
          TextButton(
            onPressed: () =>
                ref.read(devAccountSwitchProvider.notifier).clearError(),
            child: Text(es ? 'Cerrar aviso' : 'Dismiss'),
          ),
        ],
      ),
    );
  }
}

class DevAccountSwitchEntry extends ConsumerWidget {
  const DevAccountSwitchEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(devLoginAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final es = isSpanish(context);
    final loading =
        ref.watch(devAccountSwitchProvider).loading ||
        ref.watch(authControllerProvider).isLoading;
    return Column(
      children: [
        ListTile(
          key: const ValueKey('dev-switch-account'),
          leading: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.switch_account_outlined),
          title: Text(es ? 'Cambiar cuenta de prueba' : 'Switch test account'),
          subtitle: Text(
            es
                ? 'Vortice Next · Solo desarrollo'
                : 'Vortice Next · Development only',
          ),
          enabled: !loading,
          onTap: loading ? null : () => showDevAccountPicker(context, ref),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: DevAccountSwitchNotice(),
        ),
      ],
    );
  }
}
