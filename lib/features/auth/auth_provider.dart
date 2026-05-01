import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/models/profile.dart';

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

  final data = await supabase
      .from(AppConstants.tProfiles)
      .select()
      .eq('id', session.user.id)
      .maybeSingle();

  if (data == null) return null;
  return Profile.fromJson(data);
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
  static const unauthenticated = AppAuthStatus(isLoading: false, isAuthenticated: false);
}

final authStatusProvider = Provider<AppAuthStatus>((ref) {
  final authAsync = ref.watch(_supabaseAuthStreamProvider);

  return authAsync.when(
    loading: () => AppAuthStatus.loading,
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
      // Validate org code
      final org = await supabase
          .from(AppConstants.tOrgCodes)
          .select('id, code, intended_role, single_use, max_uses, use_count, expires_at, org_id')
          .eq('code', orgCode.toUpperCase())
          .maybeSingle();

      if (org == null) throw Exception('invalidOrgCode');

      // Check expiry
      final expiresAt = org['expires_at'] as String?;
      if (expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.now())) {
        throw Exception('orgCodeExpired');
      }

      // Check usage
      final singleUse = org['single_use'] as bool? ?? true;
      final maxUses = org['max_uses'] as int? ?? 1;
      final useCount = org['use_count'] as int? ?? 0;
      if (singleUse && useCount >= maxUses) {
        throw Exception('orgCodeUsed');
      }

      // Capture org_id from code (for org-scoped invites)
      final orgId = org['org_id'] as String?;

      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'org_code_used': orgCode.toUpperCase(),
          if (orgId != null) 'org_id': orgId,
        },
      );

      // Increment use count
      await supabase
          .from(AppConstants.tOrgCodes)
          .update({'use_count': useCount + 1})
          .eq('id', org['id']);

      // If org_id on code, also set it on the profile directly
      // (in case the DB trigger doesn't handle it yet)
      if (orgId != null) {
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          await supabase
              .from(AppConstants.tProfiles)
              .update({'org_id': orgId})
              .eq('id', userId);
        }
      }
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
          if (vesselName != null && vesselName.isNotEmpty) 'vessel_name': vesselName,
          if (vesselType != null && vesselType.isNotEmpty) 'vessel_type': vesselType,
          if (marinaLocation != null && marinaLocation.isNotEmpty) 'marina_location': marinaLocation,
        },
      );
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => supabase.auth.signOut());
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
    state = Locale(code);
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefLocale, locale.languageCode);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});
