import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

/// When the auth stream reloads, treat a cleared session as logged out immediately.
AppAuthStatus authStatusWhileStreamLoading(Session? currentSession) {
  if (currentSession == null) return AppAuthStatus.unauthenticated;
  return AppAuthStatus.loading;
}
