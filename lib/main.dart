import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/app.dart';
import 'package:vortice_app/core/constants.dart';
import 'package:vortice_app/core/backend_config.dart';
import 'package:vortice_app/features/auth/password_recovery.dart';
import 'package:vortice_app/core/push_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vortice_app/core/appearance_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  validateBackendConfig(AppConstants.supabaseUrl, AppConstants.supabaseAnonKey);

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
  final appearancePreferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        passwordRecoveryProvider.overrideWith((_) => recovery),
        appearancePreferencesProvider.overrideWithValue(appearancePreferences),
      ],
      child: const VorticeApp(),
    ),
  );
}
