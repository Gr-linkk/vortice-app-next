import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

class MaintenanceDocumentPage {
  MaintenanceDocumentPage(this.bytes) {
    if (bytes.length > 5 * 1024 * 1024 ||
        bytes.length < 8 ||
        !(bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255 ||
            bytes[0] == 137 &&
                bytes[1] == 80 &&
                bytes[2] == 78 &&
                bytes[3] == 71)) {
      throw const FormatException('Use a JPEG or PNG page under 5 MB');
    }
  }
  final Uint8List bytes;
  bool get png => bytes[0] == 137;
  String get extension => png ? 'png' : 'jpg';
  String get mime => png ? 'image/png' : 'image/jpeg';
}

abstract class MaintenanceDocumentsRepository {
  Future<List<Map<String, dynamic>>> list(String fleet);
  Future<void> save(
    String id,
    String fleet,
    String title,
    List<MaintenanceDocumentPage> pages,
  );
  Future<Uint8List> page(String document, int page);
}

class SupabaseMaintenanceDocumentsRepository
    implements MaintenanceDocumentsRepository {
  SupabaseMaintenanceDocumentsRepository(this.client, this.actor);
  final SupabaseClient client;
  final String actor;
  void _check() {
    if (client.auth.currentUser?.id != actor) {
      throw StateError('Account changed');
    }
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    _check();
    final result = await request().timeout(const Duration(seconds: 30));
    _check();
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> list(String fleet) async => _guard(
    () => client
        .from('maintenance_documents')
        .select(
          'id,title,created_at,maintenance_document_pages(page),agent_plan_drafts(id,draft,applied_plan_id)',
        )
        .eq('client_id', fleet)
        .eq('archived', false)
        .order('created_at', ascending: false)
        .limit(500),
  );

  @override
  Future<void> save(
    String id,
    String fleet,
    String title,
    List<MaintenanceDocumentPage> pages,
  ) async {
    if (pages.isEmpty || pages.length > 30) {
      throw StateError('Use 1 to 30 pages');
    }
    final args = {'p_id': id, 'p_client': fleet, 'p_title': title};
    await _guard(() => client.rpc('save_maintenance_document', params: args));
    final bucket = client.storage.from('maintenance-documents');
    final uploaded = (await _guard(
      () => bucket.list(path: id),
    )).map((file) => file.name).toSet();
    for (var n = 0; n < pages.length; n++) {
      final page = pages[n];
      final path = '$id/${n + 1}.${page.extension}';
      if (uploaded.contains('${n + 1}.${page.extension}')) {
        final existing = await _guard(() => bucket.download(path));
        if (sha256.convert(existing) != sha256.convert(page.bytes)) {
          throw StateError('Uploaded page changed');
        }
        continue;
      }
      try {
        await _guard(
          () => bucket.uploadBinary(
            path,
            page.bytes,
            fileOptions: FileOptions(
              contentType: page.mime,
              upsert: false,
              cacheControl: '0',
            ),
          ),
        );
      } on StorageException catch (error) {
        if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
        // An uncertain upload may have succeeded. Never overwrite source bytes.
        final existing = await _guard(() => bucket.download(path));
        if (sha256.convert(existing) != sha256.convert(page.bytes)) {
          throw StateError('Uploaded page changed');
        }
      }
    }
    await _guard(
      () => client.rpc(
        'save_maintenance_document',
        params: {...args, 'p_pages': pages.length},
      ),
    );
  }

  @override
  Future<Uint8List> page(String document, int page) async {
    final row = await _guard(
      () => client
          .from('maintenance_document_pages')
          .select('object_path')
          .eq('document_id', document)
          .eq('page', page)
          .single(),
    );
    return _guard(
      () => client.storage
          .from('maintenance-documents')
          .download(row['object_path'] as String),
    );
  }
}

final maintenanceDocumentsRepositoryProvider =
    Provider<MaintenanceDocumentsRepository>(
      (ref) => SupabaseMaintenanceDocumentsRepository(
        supabase,
        ref.watch(sessionProvider)?.user.id ?? '',
      ),
    );
