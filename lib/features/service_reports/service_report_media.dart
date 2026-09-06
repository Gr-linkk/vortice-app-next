import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

/// Supports stored object paths and URLs written by older app versions.
String? serviceReportObjectPath(
  String reference,
  String bucket,
  String baseUrl,
) {
  final uri = Uri.tryParse(reference);
  if (uri == null) return null;
  if (!uri.hasScheme && !reference.startsWith('//')) return reference;
  final base = Uri.parse(baseUrl);
  if (uri.scheme != base.scheme || uri.authority != base.authority) return null;
  for (final access in ['public', 'sign', 'authenticated']) {
    final prefix = '/storage/v1/object/$access/$bucket/';
    if (uri.path.startsWith(prefix)) {
      return Uri.decodeComponent(uri.path.substring(prefix.length));
    }
  }
  return null;
}

Future<String> resolveServiceReportMedia(
  SupabaseClient client,
  String bucket,
  String reference,
) async {
  final path = serviceReportObjectPath(
    reference,
    bucket,
    client.storage.from(bucket).getPublicUrl(''),
  );
  if (path == null) return reference;
  return client.storage.from(bucket).createSignedUrl(path, 300);
}

typedef ServiceReportMedia = ({String bucket, String reference});

final serviceReportMediaProvider = FutureProvider.autoDispose
    .family<String, ServiceReportMedia>((ref, media) {
      ref.watch(profileProvider);
      return resolveServiceReportMedia(supabase, media.bucket, media.reference);
    });

class ServiceReportImage extends ConsumerWidget {
  const ServiceReportImage({
    super.key,
    required this.bucket,
    required this.reference,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  final String bucket;
  final String reference;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = (bucket: bucket, reference: reference);
    final url = ref.watch(serviceReportMediaProvider(media));
    Widget retry() => Center(
      child: IconButton(
        tooltip: Localizations.localeOf(context).languageCode == 'es'
            ? 'Reintentar imagen'
            : 'Retry image',
        onPressed: () => ref.invalidate(serviceReportMediaProvider(media)),
        icon: const Icon(Icons.refresh),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: url.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => retry(),
        data: (value) => Image.network(
          value,
          fit: fit,
          errorBuilder: (_, __, ___) => retry(),
        ),
      ),
    );
  }
}
