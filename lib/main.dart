import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/app.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/features/auth/password_recovery.dart';
import 'package:vortice_app/core/push_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConstants.supabaseUrl.isEmpty ||
      AppConstants.supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing isolated backend configuration. Pass SUPABASE_URL and '
      'SUPABASE_ANON_KEY with --dart-define. Do not use the original '
      'Vortice Supabase project.',
    );
  }

  // Supabase: this independent project requires an explicit backend target.
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
      detectSessionInUri: false,
    ),
  );

  final recovery = PasswordRecoveryController();
  await recovery.start();
  await PushNotifications.instance.initialize();
  runApp(
    ProviderScope(
      overrides: [passwordRecoveryProvider.overrideWith((_) => recovery)],
      child: const VorticeApp(),
    ),
  );
}
