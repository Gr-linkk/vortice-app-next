import 'package:supabase_flutter/supabase_flutter.dart';

/// Convenience accessor — use `supabase.from(...)` throughout the app.
SupabaseClient get supabase => Supabase.instance.client;
