import 'package:flutter/material.dart';
import 'package:vortice_app/core/push_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/features/auth/auth_status_logic.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/profile.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/l10n/app_localizations.dart';

// ── Auth change stream ─────────────────────────────────────────────────────

final _supabaseAuthStreamProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

// ── Session ────────────────────────────────────────────────────────────────

final sessionProvider = Provider<Session?>((ref) {
  final asyncAuth = ref.watch(_supabaseAuthStreamProvider);
  return asyncAuth.when(
    data: (state) => state.session,
    loading: () => supabase.auth.currentSession,
    error: (_, __) => null,
  );
});

// ── Profile ────────────────────────────────────────────────────────────────

final profileProvider = FutureProvider<Profile?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;

  final cache = AccountJsonCache(
    session.user.id,
    () => supabase.auth.currentUser?.id,
  );
  final data = await cache.readThrough(
    'profile',
    () => supabase
        .from(AppConstants.tProfiles)
        .select()
        .eq('id', session.user.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 6)),
  );

  if (data == null) return null;
  final row = Map<String, dynamic>.from(data as Map);
  if (row['role'] == 'member') {
    // The membership context shares the account cache epoch. A changed server
    // membership clears old company reads; offline reads keep only that scope.
    // Mutation authority always comes from the server, including revocation.
    final raw = await cache.readThrough(
      'organization_context',
      () => supabase
          .rpc('organization_context')
          .timeout(const Duration(seconds: 6)),
    );
    final context = Map<String, dynamic>.from(raw as Map);
    await cache.save('profile', row);
    row['role'] = context['route_role'];
    row['org_id'] = context['active_organization_id'];
    row['membership_managed'] = true;
    row['onboarding_required'] = context['onboarding_required'] == true;
    row['organization_roles'] = context['roles'] ?? <String>[];
    row['organization_permissions'] = context['permissions'] ?? <String>[];
  }
  return Profile.fromJson(row);
});

// ── Unified auth status (used by the router) ───────────────────────────────

class AppAuthStatus {
  final bool isLoading;
  final bool isAuthenticated;
  final Profile? profile;

  const AppAuthStatus({
    required this.isLoading,
    required this.isAuthenticated,
    this.profile,
  });

  static const loading = AppAuthStatus(isLoading: true, isAuthenticated: false);
  static const unauthenticated = AppAuthStatus(
    isLoading: false,
    isAuthenticated: false,
  );
}

final authStatusProvider = Provider<AppAuthStatus>((ref) {
  final authAsync = ref.watch(_supabaseAuthStreamProvider);

  return authAsync.when(
    loading: () => authStatusWhileStreamLoading(supabase.auth.currentSession),
    error: (_, __) => AppAuthStatus.unauthenticated,
    data: (auth) {
      if (auth.session == null) return AppAuthStatus.unauthenticated;

      final profileAsync = ref.watch(profileProvider);
      return profileAsync.when(
        loading: () => AppAuthStatus.loading,
        error: (_, __) => AppAuthStatus.unauthenticated,
        data: (profile) => AppAuthStatus(
          isLoading: false,
          isAuthenticated: profile != null,
          profile: profile,
        ),
      );
    },
  );
});

// ── Auth controller — sign in / sign up / sign out ─────────────────────────

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController() : super(const AsyncData(null));

  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.signInWithPassword(email: email, password: password);
    });
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String orgCode,
    required String fullName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // The server validates and consumes the code atomically. Clients cannot
      // choose their own role, organization or edit invitation usage counters.
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'org_code_used': orgCode.trim().toUpperCase(),
        },
      );
    });
  }

  Future<void> signUpFreeClient({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? vesselName,
    String? vesselType,
    String? marinaLocation,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': 'client',
          'subscription_tier': 0,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (vesselName != null && vesselName.isNotEmpty)
            'vessel_name': vesselName,
          if (vesselType != null && vesselType.isNotEmpty)
            'vessel_type': vesselType,
          if (marinaLocation != null && marinaLocation.isNotEmpty)
            'marina_location': marinaLocation,
        },
      );
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final account = supabase.auth.currentUser?.id;
      await PushNotifications.instance.detach();
      if (account != null) await invalidateAccountReadCaches(account);
      await supabase.auth.signOut();
    });
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
      return AuthController();
    });

// ── Locale ─────────────────────────────────────────────────────────────────

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(AppConstants.prefLocale) ?? 'en';
    state = AppLocalizations.supportedLocales.firstWhere(
      (locale) => locale.languageCode == code,
      orElse: () => const Locale('en'),
    );
  }

  Future<void> setLocale(Locale locale) async {
    final supported = AppLocalizations.supportedLocales.firstWhere(
      (candidate) => candidate.languageCode == locale.languageCode,
      orElse: () => const Locale('en'),
    );
    state = supported;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefLocale, supported.languageCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});
