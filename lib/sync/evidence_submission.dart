import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';
import 'package:vortice_app/core/constants.dart';
import 'field_work_queue.dart';

Future<FieldOperation> prepareEvidenceSubmission({
  required FieldWorkQueue queue,
  required String kind,
  required String record,
  required Map<String, dynamic> data,
  required List<Uint8List> photos,
  Uint8List? signature,
}) async {
  final previous = (await queue.list())
      .where((row) => row.subject == record && row.kind == '${kind}_submission')
      .lastOrNull;
  if (previous != null && previous.status != 'cancelled') {
    final uploads = (previous.payload['uploads'] as List).cast<Map>();
    final oldPhotos = uploads
        .where((u) => u['bucket'] != 'signatures')
        .map((u) => u['bytes'])
        .toList();
    final oldSignature = uploads
        .where((u) => u['bucket'] == 'signatures')
        .firstOrNull?['bytes'];
    if (jsonEncode(previous.payload['p_data']) != jsonEncode(data) ||
        jsonEncode(oldPhotos) !=
            jsonEncode(photos.map(base64Encode).toList()) ||
        oldSignature != (signature == null ? null : base64Encode(signature))) {
      throw StateError(
        'This submission is already saved. Open Saved work and sync to correct it first.',
      );
    }
    return previous;
  }
  final id = const Uuid().v4();
  return FieldOperation(
    id: id,
    kind: '${kind}_submission',
    subject: record,
    payload: evidenceSubmissionPayload(
      kind: kind,
      operation: id,
      record: record,
      data: data,
      photos: photos,
      signature: signature,
      expectedSubmission: previous?.id,
    ),
  );
}

Map<String, dynamic> evidenceSubmissionPayload({
  required String kind,
  required String operation,
  required String record,
  required Map<String, dynamic> data,
  required List<Uint8List> photos,
  Uint8List? signature,
  String? expectedSubmission,
}) => {
  'p_data': data,
  'expected_submission': expectedSubmission,
  'uploads': [
    for (var index = 0; index < photos.length; index++)
      {
        'bucket': kind == 'request'
            ? 'service-request-photos'
            : 'service-report-photos',
        'path':
            '$record/$operation/${index}_${sha256.convert(photos[index])}.jpg',
        'contentType': 'image/jpeg',
        'bytes': base64Encode(photos[index]),
      },
    if (signature != null)
      {
        'bucket': 'signatures',
        'path':
            '${data['work_order_id']}_${operation}_${sha256.convert(signature)}.png',
        'contentType': 'image/png',
        'bytes': base64Encode(signature),
      },
  ],
};

/// Each step can lose its response. Immutable paths and checked RPC receipts
/// let the durable outbox repeat the entire sequence without another record.
class EvidenceSubmissionTransport {
  EvidenceSubmissionTransport({
    required this.client,
    required this.headers,
    required this.checkAccount,
    this.baseUrl = AppConstants.supabaseUrl,
  });
  final http.Client client;
  final Map<String, String> headers;
  final void Function() checkAccount;
  final String baseUrl;

  Future<void> send(FieldOperation operation) async {
    final kind = operation.kind == 'request_submission' ? 'request' : 'report';
    final data = Map<String, dynamic>.from(operation.payload['p_data'] as Map);
    await _rpc('begin_${kind}_submission', {
      'p_operation': operation.id,
      kind == 'request' ? 'p_request' : 'p_report': operation.subject,
      'p_data': data,
      'p_expected_submission': operation.payload['expected_submission'],
    });
    final photos = <String>[];
    String? signature;
    for (final raw in operation.payload['uploads'] as List) {
      final upload = Map<String, dynamic>.from(raw as Map);
      final bucket = upload['bucket'] as String;
      final path = upload['path'] as String;
      if (![
            'service-request-photos',
            'service-report-photos',
            'signatures',
          ].contains(bucket) ||
          path.contains('..') ||
          path.startsWith('/')) {
        throw const FormatException('Invalid evidence destination');
      }
      checkAccount();
      final bytes = base64Decode(upload['bytes'] as String);
      final response = await client
          .post(
            Uri.parse('$baseUrl/storage/v1/object/$bucket/$path'),
            headers: {
              ...headers,
              'Content-Type': upload['contentType'] as String,
              'x-upsert': 'false',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 25));
      if ([400, 403, 409].contains(response.statusCode)) {
        final existing = await client
            .get(
              Uri.parse(
                '$baseUrl/storage/v1/object/authenticated/$bucket/$path',
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 25));
        _checkResponse(existing);
        if (base64Encode(existing.bodyBytes) != upload['bytes']) {
          throw StateError('Stored evidence differs from this submission.');
        }
      } else {
        _checkResponse(response);
      }
      checkAccount();
      if (bucket == 'signatures') {
        signature = path;
      } else {
        photos.add(path);
      }
    }
    await _rpc('finish_evidence_submission', {
      'p_operation': operation.id,
      'p_record': operation.subject,
      'p_kind': kind,
      'p_photos': photos,
      'p_signature': signature,
    });
  }

  Future<void> _rpc(String name, Map<String, dynamic> data) async {
    checkAccount();
    final response = await client
        .post(
          Uri.parse('$baseUrl/rest/v1/rpc/$name'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 20));
    _checkResponse(response);
    checkAccount();
  }
}

void _checkResponse(http.Response response) {
  if (response.statusCode >= 500 || response.statusCode == 429) {
    throw http.ClientException('Service temporarily unavailable.');
  }
  if (response.statusCode >= 400) {
    Map<String, dynamic> error = {};
    try {
      error = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    throw PostgrestException(
      message: error['message']?.toString() ?? 'Evidence rejected',
      code: error['code']?.toString(),
    );
  }
}
