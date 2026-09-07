import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/checklists/saved_checklists_repository.dart';
import 'package:vortice_app/models/saved_checklist.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

final savedChecklistsForAssetProvider = FutureProvider.family
    .autoDispose<
      List<SavedChecklist>,
      ({String assetId, SavedChecklistType? type})
    >((ref, args) {
      ref.watch(sessionProvider);
      return ref
          .watch(savedChecklistsRepositoryProvider)
          .listForAsset(args.assetId, checklistType: args.type);
    });
