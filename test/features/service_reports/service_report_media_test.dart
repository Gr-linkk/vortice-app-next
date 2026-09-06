import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/features/service_reports/service_report_media.dart';

void main() {
  const base = 'https://example.invalid';
  test('recognizes paths and old bucket URLs without signing unrelated URLs', () {
    expect(
      serviceReportObjectPath('report/photo.png', 'signatures', base),
      'report/photo.png',
    );
    for (final access in ['public', 'sign', 'authenticated']) {
      expect(
        serviceReportObjectPath(
          '$base/storage/v1/object/$access/signatures/test%20image.png?token=old',
          'signatures',
          base,
        ),
        'test image.png',
      );
    }
    expect(
      serviceReportObjectPath(
        '$base/storage/v1/object/public/other/file.png',
        'signatures',
        base,
      ),
      isNull,
    );
    expect(
      serviceReportObjectPath(
        'https://another.invalid/storage/v1/object/public/signatures/file.png',
        'signatures',
        base,
      ),
      isNull,
    );
  });

  test('private report media requests a fresh signed URL', () async {
    late http.Request sent;
    final client = SupabaseClient(
      base,
      'test-key',
      httpClient: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'signedURL': '/object/sign/signatures/test.png?token=fresh',
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final result = await resolveServiceReportMedia(
      client,
      'signatures',
      '$base/storage/v1/object/public/signatures/test.png',
    );
    expect(sent.url.path, '/storage/v1/object/sign/signatures/test.png');
    expect(jsonDecode(sent.body)['expiresIn'], 300);
    expect(result, contains('/object/sign/signatures/test.png?token=fresh'));
  });
}
