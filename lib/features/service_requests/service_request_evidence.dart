import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

String requestPhotoPath(String value, String requestId) {
  const origin = 'https://hkjpojobdbbtjkhaudki.supabase.co';
  const prefix = '/storage/v1/object/public/service-request-photos/';
  final uri = Uri.tryParse(value);
  if (uri == null) throw const FormatException('Invalid evidence');
  var path = value;
  if (uri.hasScheme) {
    if (uri.origin != origin || !uri.path.startsWith(prefix)) {
      throw const FormatException('Evidence belongs to another service');
    }
    path = Uri.decodeComponent(uri.path.substring(prefix.length));
  }
  if (!path.startsWith('$requestId/') ||
      path.split('/').length != 2 ||
      path.contains('..') ||
      path.contains('?') ||
      path.contains('#') ||
      path.endsWith('/')) {
    throw const FormatException('Evidence does not belong to this request');
  }
  return path;
}

typedef RequestEvidence = ({String requestId, String path});
final requestEvidenceProvider = FutureProvider.autoDispose
    .family<Uint8List, RequestEvidence>((ref, query) async {
      final profile = await ref.watch(profileProvider.future);
      if (profile == null) throw StateError('Sign in to view evidence');
      return supabase.storage
          .from('service-request-photos')
          .download(requestPhotoPath(query.path, query.requestId));
    });

class RequestEvidencePhoto extends ConsumerWidget {
  const RequestEvidencePhoto({
    super.key,
    required this.requestId,
    required this.path,
  });
  final String requestId, path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (requestId: requestId, path: path);
    return ref
        .watch(requestEvidenceProvider(query))
        .when(
          data: (bytes) =>
              Image.memory(bytes, width: 76, height: 76, fit: BoxFit.cover),
          loading: () => const SizedBox(
            width: 76,
            height: 76,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => SizedBox(
            width: 76,
            height: 76,
            child: IconButton(
              tooltip: Localizations.localeOf(context).languageCode == 'es'
                  ? 'Reintentar foto'
                  : 'Retry photo',
              onPressed: () => ref.invalidate(requestEvidenceProvider(query)),
              icon: const Icon(Icons.broken_image_outlined),
            ),
          ),
        );
  }
}

final workRequestEvidenceProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
      if (await ref.watch(profileProvider.future) == null) return [];
      return List<Map<String, dynamic>>.from(
        await supabase
            .from('service_requests')
            .select('id,photo_urls')
            .eq('generated_work_order_id', id),
      );
    });

class WorkRequestEvidence extends ConsumerWidget {
  const WorkRequestEvidence({super.key, required this.workOrderId});
  final String workOrderId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(workRequestEvidenceProvider(workOrderId))
      .when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => TextButton.icon(
          onPressed: () =>
              ref.invalidate(workRequestEvidenceProvider(workOrderId)),
          icon: const Icon(Icons.refresh),
          label: Text(
            Localizations.localeOf(context).languageCode == 'es'
                ? 'Reintentar fotos de solicitud'
                : 'Retry request photos',
          ),
        ),
        data: (rows) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final row in rows)
              for (final path in (row['photo_urls'] as List? ?? []))
                RequestEvidencePhoto(
                  requestId: row['id'] as String,
                  path: path as String,
                ),
          ],
        ),
      );
}
