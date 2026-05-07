import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/checklists/saved_checklists_repository.dart';
import 'package:vortice_app/models/saved_checklist.dart';

final savedChecklistsForAssetProvider = FutureProvider.family.autoDispose<
    List<SavedChecklist>, ({String assetId, SavedChecklistType? type})>(
  (ref, args) {
    return ref
        .watch(savedChecklistsRepositoryProvider)
        .listForAsset(args.assetId, checklistType: args.type);
  },
);
