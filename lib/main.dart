import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/app.dart';
import 'package:vortice_app/core/constants.dart';

// Firebase is initialized separately after running `flutterfire configure`.
// See docs/SETUP.md for instructions.
//
// Once google-services.json (Android) and GoogleService-Info.plist (iOS) are
// added and `flutterfire configure` is run to generate lib/firebase_options.dart,
// uncomment the Firebase block below.
//
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'firebase_options.dart';
//
// @pragma('vm:entry-point')
// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
// }

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

  // --- Firebase (uncomment once flutterfire configure is complete) ---
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Supabase: this independent project requires an explicit backend target.
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
  );

  runApp(const ProviderScope(child: VorticeApp()));
}
