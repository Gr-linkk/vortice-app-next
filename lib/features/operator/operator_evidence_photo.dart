import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';
import 'package:vortice_app/sync/field_work_provider.dart';
import 'dart:convert';

final operatorEvidenceProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, path) async {
      final account = ref.watch(sessionProvider)?.user.id;
      if (account == null) throw StateError('Sign in to view evidence');
      final local = (await ref.read(fieldWorkQueueProvider)?.list() ?? [])
          .where(
            (r) =>
                r.kind == 'upload' &&
                r.payload['bucket'] == 'operator-evidence' &&
                r.payload['path'] == path,
          )
          .firstOrNull;
      if (local != null) return base64Decode(local.payload['bytes'] as String);
      return supabase.storage.from('operator-evidence').download(path);
    });

class OperatorEvidencePhoto extends ConsumerWidget {
  const OperatorEvidencePhoto({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(operatorEvidenceProvider(path))
      .when(
        data: (bytes) => Padding(
          padding: const EdgeInsets.all(8),
          child: Image.memory(
            bytes,
            height: 180,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined),
          ),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (_, __) => TextButton.icon(
          onPressed: () => ref.invalidate(operatorEvidenceProvider(path)),
          icon: const Icon(Icons.refresh),
          label: Text(isSpanish(context) ? 'Reintentar foto' : 'Retry photo'),
        ),
      );
}
