import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/operator/operator_checklist_screen_state.dart';

class OperatorChecklistScreen extends ConsumerStatefulWidget {
  final String? initialAssetId;
  final String? initialTemplateId;

  const OperatorChecklistScreen({
    super.key,
    this.initialAssetId,
    this.initialTemplateId,
  });

  @override
  ConsumerState<OperatorChecklistScreen> createState() =>
      OperatorChecklistScreenState();
}
