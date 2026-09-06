import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/features/invoices/invoice_provider.dart';
import 'package:vortice_app/models/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('invoice list and direct view discard previous-account data', () async {
    SharedPreferences.setMockInitialValues({});
    var owningAccount = true;
    var queries = 0;
    await Supabase.initialize(
      url: 'https://example.invalid',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        queries++;
        return http.Response(
          jsonEncode(
            owningAccount
                ? [
                    {
                      'id': 'invoice-a',
                      'work_order_id': 'job-a',
                      'client_id': 'company-a',
                      'invoice_number': 'PRIVATE-A',
                      'status': 'draft',
                    },
                  ]
                : [],
          ),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final account = StateProvider<Profile?>(
      (_) => const Profile(
        id: 'owner',
        email: 'owner@example.invalid',
        fullName: 'Owner',
        role: UserRole.owner,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        profileProvider.overrideWith((ref) async => ref.watch(account)),
      ],
    );
    try {
      expect(
        (await container.read(invoicesProvider.future)).single.invoiceNumber,
        'PRIVATE-A',
      );
      expect(
        (await container.read(
          invoiceByIdProvider('invoice-a').future,
        ))?.invoiceNumber,
        'PRIVATE-A',
      );
      owningAccount = false;
      container.read(account.notifier).state = const Profile(
        id: 'client-b',
        email: 'b@example.invalid',
        fullName: 'Company B',
        role: UserRole.client,
      );
      await container.pump();
      expect(await container.read(invoicesProvider.future), isEmpty);
      expect(
        await container.read(invoiceByIdProvider('invoice-a').future),
        isNull,
      );
      expect(queries, 4);
      container.read(account.notifier).state = null;
      await container.pump();
      expect(await container.read(invoicesProvider.future), isEmpty);
      expect(
        await container.read(invoiceByIdProvider('invoice-a').future),
        isNull,
      );
      expect(
        queries,
        4,
        reason: 'Signed-out views must not query or expose old rows',
      );
    } finally {
      container.dispose();
      await Supabase.instance.dispose();
    }
  });
}
