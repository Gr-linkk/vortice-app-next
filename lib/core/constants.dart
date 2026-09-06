class AppConstants {
  AppConstants._();

  // ── Supabase ──────────────────────────────────────────────────────────────
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  // ── Table names ────────────────────────────────────────────────────────────
  static const String tOrgCodes = 'org_codes';
  static const String tProfiles = 'profiles';
  static const String tAssetTypes = 'asset_types';
  static const String tAssets = 'assets';
  static const String tAssetEngines = 'asset_engines';
  static const String tAssetServiceIntervals = 'asset_service_intervals';
  static const String tImportedDocs = 'imported_docs';
  static const String tChecklistTemplates = 'checklist_templates';
  static const String tChecklistItems = 'checklist_items';
  static const String tWorkOrders = 'work_orders';
  static const String tWorkOrderChecklistSnapshots =
      'work_order_checklist_snapshots';
  static const String tChecklistResponses = 'checklist_responses';
  static const String tServiceReports = 'service_reports';
  static const String tServiceReportPhotos = 'service_report_photos';
  static const String tParts = 'parts';
  static const String tPartsCatalog = 'parts_catalog';
  static const String tInvoices = 'invoices';
  static const String tMaintenanceRequests = 'maintenance_requests';
  static const String tOperatorChecklistRuns = 'operator_checklist_runs';
  static const String tOperatorChecklistResponses =
      'operator_checklist_responses';
  static const String tSavedChecklists = 'saved_checklists';
  static const String tServiceReminders = 'service_reminders';
  static const String tHourLogs = 'hour_logs';
  static const String tTelemetryReadings = 'telemetry_readings';
  static const String tTelemetryAlerts = 'telemetry_alerts';
  static const String tDevices = 'devices';
  static const String tClientCapabilities = 'client_capabilities';
  static const String tPmPartsRequirements = 'pm_parts_requirements';
  static const String tPartsInventory = 'parts_inventory';
  static const String tNotifications = 'notifications';

  // ── Storage buckets ────────────────────────────────────────────────────────
  static const String bucketSignatures = 'signatures';
  static const String bucketReportPhotos = 'service-report-photos';
  static const String bucketServiceRequestPhotos = 'service-request-photos';

  // ── SharedPreferences keys ─────────────────────────────────────────────────
  static const String prefLocale = 'app_locale';

  // ── App metadata ───────────────────────────────────────────────────────────
  static const String appVersion = '1.4.1+11';
  static const String supportEmail = 'soporte@vorticemechanical.com';

  // ── Invoice defaults ──────────────────────────────────────────────────────
  static const double defaultPartsMarkupPct = 15.0;
  static const double defaultBillableRate = 60.0;

  // ── Additional table names ────────────────────────────────────────────────
  static const String tWorkOrderAssignments = 'work_order_assignments';
  static const String tClientOrgs = 'client_orgs';
  static const String tMeetingRequests = 'meeting_requests';
  static const String tServiceRequests = 'service_requests';
}
