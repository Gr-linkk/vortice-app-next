import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/features/service_reports/service_report_screen_state.dart';

class ServiceReportScreen extends ConsumerStatefulWidget {
  final String? initialWorkOrderId;
  final String? draftStorageKey;

  const ServiceReportScreen({
    super.key,
    this.initialWorkOrderId,
    this.draftStorageKey,
  });

  @override
  ConsumerState<ServiceReportScreen> createState() =>
      ServiceReportScreenState();
}
