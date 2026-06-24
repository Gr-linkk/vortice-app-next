// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get loginSubtitle => 'Marine & Heavy Equipment Maintenance';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get signIn => 'Sign In';

  @override
  String get forgotPassword => 'Forgot Password?';

  @override
  String get noAccount => 'Don\'t have an account?';

  @override
  String get register => 'Register';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get invalidEmail => 'Please enter a valid email address';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get registerTitle => 'Create Account';

  @override
  String get registerSubtitle => 'Enter your organization code to get started.';

  @override
  String get iHaveOrgCode => 'I have an org code';

  @override
  String get newClientSignup => 'New client signup';

  @override
  String get orgCode => 'Organization Code';

  @override
  String get orgCodeHelper => 'Ask your account manager for this code';

  @override
  String get fullName => 'Full Name';

  @override
  String get phone => 'Phone';

  @override
  String get vesselName => 'Vessel Name';

  @override
  String get vesselType => 'Vessel Type';

  @override
  String get marinaLocation => 'Marina / Location';

  @override
  String get vesselTypeSailboat => 'Sailboat';

  @override
  String get vesselTypePowerboat => 'Powerboat';

  @override
  String get vesselTypeYacht => 'Yacht';

  @override
  String get vesselTypeOther => 'Other';

  @override
  String get confirmPassword => 'Confirm Password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get invalidOrgCode =>
      'Invalid organization code. Please check and try again.';

  @override
  String get createAccount => 'Create Account';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String greeting(String name) {
    return 'Hello, $name';
  }

  @override
  String get ownerDashboardTitle => 'Dashboard';

  @override
  String get employeeDashboardTitle => 'My Work Queue';

  @override
  String get clientDashboardTitle => 'My Equipment';

  @override
  String get operatorDashboardTitle => 'Daily Operations';

  @override
  String get clientDashboardSubtitle => 'Track your fleet and service history.';

  @override
  String get operatorDashboardSubtitle =>
      'Start your daily checklist or report an issue.';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navAssets => 'Assets';

  @override
  String get navWorkOrders => 'Work Orders';

  @override
  String get navServiceReports => 'Reports';

  @override
  String get navParts => 'Parts';

  @override
  String get navInvoices => 'Invoices';

  @override
  String get navChecklist => 'Checklist';

  @override
  String get navFlags => 'Flags';

  @override
  String get totalAssets => 'Total Assets';

  @override
  String get openWorkOrders => 'Open Orders';

  @override
  String get recentWorkOrders => 'Recent Work Orders';

  @override
  String get viewAll => 'View All';

  @override
  String get noWorkOrders => 'No work orders found.';

  @override
  String get assignedToMe => 'Assigned to Me';

  @override
  String get noAssignedWorkOrders => 'No active work orders assigned to you.';

  @override
  String get myFleet => 'My Fleet';

  @override
  String get noAssets => 'No assets found.';

  @override
  String get availableAssets => 'Available Assets';

  @override
  String get activeServices => 'Active Services';

  @override
  String get assetsTitle => 'Assets';

  @override
  String get assetType => 'Asset Type';

  @override
  String get searchAssets => 'Search assets...';

  @override
  String get addAsset => 'Add Asset';

  @override
  String get saveAsset => 'Save Asset';

  @override
  String get assetDetail => 'Asset Detail';

  @override
  String get assetDetails => 'Details';

  @override
  String get assetName => 'Asset Name';

  @override
  String get serialNumber => 'Serial Number';

  @override
  String get model => 'Model';

  @override
  String get manufacturer => 'Manufacturer';

  @override
  String get year => 'Year';

  @override
  String get location => 'Location';

  @override
  String get status => 'Status';

  @override
  String get notes => 'Notes';

  @override
  String get assetNotFound => 'Asset not found.';

  @override
  String get invalidYear => 'Please enter a valid year';

  @override
  String get editAsset => 'Edit Asset';

  @override
  String get addEngineHint => 'Add the primary engine (you can add more later)';

  @override
  String get reassignTech => 'Reassign Tech';

  @override
  String get srComplaint => '1 — Complaint';

  @override
  String get srComplaintSub => 'Client\'s reported issue in their words';

  @override
  String get srCause => '2 — Cause';

  @override
  String get srCauseSub => 'Diagnosed root cause of the problem';

  @override
  String get srCorrection => '3 — Correction';

  @override
  String get srCorrectionSub => 'Work performed and parts replaced';

  @override
  String get srSecondaryDamage => '4 — Contingent Damage';

  @override
  String get srSecondaryDamageSub =>
      'Contingent damage caused by or discovered during this job';

  @override
  String get srComments => '5 — Comments';

  @override
  String get srCommentsSub => 'Recommendations, next service, items to watch';

  @override
  String get srComplaintHint => 'What did the client report?';

  @override
  String get srCauseHint => 'What caused the issue?';

  @override
  String get srCorrectionHint => 'What work was done? What was replaced?';

  @override
  String get srSecondaryDamageHint =>
      'Contingent damage caused by the primary work or findings outside the main scope';

  @override
  String get srCommentsHint => 'Anything the client should know or watch for';

  @override
  String get workOrdersTitle => 'Work Orders';

  @override
  String get workOrderDetail => 'Work Order';

  @override
  String get workOrderTitle => 'Title';

  @override
  String get createWorkOrder => 'Create Work Order';

  @override
  String get linkedAsset => 'Linked Asset';

  @override
  String get noAsset => 'No asset';

  @override
  String get description => 'Description';

  @override
  String get jobType => 'Job Type';

  @override
  String get scheduledDate => 'Scheduled Date';

  @override
  String get priority => 'Priority';

  @override
  String get dueDate => 'Due Date';

  @override
  String get completedAt => 'Completed';

  @override
  String get selectDate => 'Select a date';

  @override
  String get startWorkOrder => 'Start Work Order';

  @override
  String get reopenWorkOrder => 'Reopen Work Order';

  @override
  String get completeWorkOrder => 'Mark Completed';

  @override
  String get statusOpen => 'Open';

  @override
  String get statusInProgress => 'In Progress';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get actions => 'Actions';

  @override
  String get viewChecklist => 'View Checklist';

  @override
  String get serviceReport => 'Service Report';

  @override
  String get selectWorkOrder => 'Please select a work order';

  @override
  String get linkedWorkOrder => 'Linked Work Order';

  @override
  String get notFound => 'Not found.';

  @override
  String get woDetailsSection => 'Details';

  @override
  String get assignedTech => 'Assigned Tech';

  @override
  String get hoursAtStart => 'Engine Hours (Start)';

  @override
  String get hoursAtEnd => 'Engine Hours (End)';

  @override
  String get labourHours => 'Labour Hours';

  @override
  String get billableRate => 'Billable Rate';

  @override
  String get wageRate => 'Wage Rate';

  @override
  String get internalNotes => 'Internal Notes';

  @override
  String get onHoldReason => 'On-Hold Reason';

  @override
  String get editWorkOrder => 'Edit Work Order';

  @override
  String get checklistTitle => 'Checklist';

  @override
  String get selectTemplate => 'Select Template';

  @override
  String get noChecklistTemplates => 'No checklist templates available.';

  @override
  String get checklistSubmitted => 'Checklist submitted successfully.';

  @override
  String get submitChecklist => 'Submit Checklist';

  @override
  String get completeChecklist => 'Complete Checklist';

  @override
  String get change => 'Change';

  @override
  String get startChecklist => 'Start Checklist';

  @override
  String get serviceReportTitle => 'Service Report';

  @override
  String get technicianNotes => 'Technician Notes';

  @override
  String get hoursWorked => 'Hours Worked';

  @override
  String get technicianSignature => 'Technician Signature';

  @override
  String get signHere => 'Sign here';

  @override
  String get clearSignature => 'Clear';

  @override
  String get saveSignature => 'Save Signature';

  @override
  String get signatureSaved => 'Signature saved.';

  @override
  String get signatureCaptured => 'Signature captured';

  @override
  String get submitReport => 'Submit Report';

  @override
  String get reportSubmitted => 'Report submitted successfully.';

  @override
  String get invalidNumber => 'Please enter a valid number';

  @override
  String get partsTitle => 'Parts Log';

  @override
  String get partName => 'Part Name';

  @override
  String get partNumber => 'Part Number';

  @override
  String get quantity => 'Qty';

  @override
  String get unitCost => 'Unit Cost';

  @override
  String get supplier => 'Supplier';

  @override
  String get addPart => 'Add Part';

  @override
  String get noParts => 'No parts logged.';

  @override
  String get invoicesTitle => 'Invoices';

  @override
  String get invoiceNumber => 'Invoice #';

  @override
  String get amount => 'Amount';

  @override
  String get overdue => 'Overdue';

  @override
  String get unpaid => 'Unpaid';

  @override
  String get paid => 'Paid';

  @override
  String get draft => 'Draft';

  @override
  String get markPaid => 'Mark Paid';

  @override
  String get noInvoices => 'No invoices found.';

  @override
  String get operatorChecklistTitle => 'Daily Checklist';

  @override
  String get selectAsset => 'Select Asset';

  @override
  String get maintenanceFlagTitle => 'Flag for Maintenance';

  @override
  String get flagInfo =>
      'Flagged issues are sent directly to the maintenance team.';

  @override
  String get issueDescription => 'Describe the issue';

  @override
  String get flagIssue => 'Flag Issue';

  @override
  String get flagSubmitted => 'Issue flagged successfully.';

  @override
  String get submitFlag => 'Submit Flag';

  @override
  String get priorityLow => 'Low';

  @override
  String get priorityMedium => 'Medium';

  @override
  String get priorityHigh => 'High';

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String get confirmDeleteMessage => 'This action cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get retry => 'Retry';

  @override
  String get search => 'Search';

  @override
  String get back => 'Back';

  @override
  String get done => 'Done';

  @override
  String get signOut => 'Sign Out';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Español';

  @override
  String get enginesTitle => 'Engines';

  @override
  String get noEngines => 'No engines found.';

  @override
  String get addEngine => 'Add Engine';

  @override
  String get editEngine => 'Edit Engine';

  @override
  String get engineLabel => 'Label';

  @override
  String get engineKind => 'Type';

  @override
  String get currentHours => 'Current Hours';

  @override
  String get enginesCount => 'engines';

  @override
  String get hourLogsTitle => 'Hour Log';

  @override
  String get noHourLogs => 'No hour entries logged.';

  @override
  String get logHours => 'Log Hours';

  @override
  String get clientsTitle => 'Clients';

  @override
  String get searchClients => 'Search clients...';

  @override
  String get noClients => 'No clients found.';

  @override
  String get clientDetails => 'Client Details';

  @override
  String get orgCodesTitle => 'Org Codes';

  @override
  String get noOrgCodes => 'No org codes found.';

  @override
  String get createOrgCode => 'Create Org Code';

  @override
  String get intendedRole => 'Intended Role';

  @override
  String get maxUses => 'Max Uses';

  @override
  String get singleUse => 'Single Use';

  @override
  String get expirationDate => 'Expiration Date (optional)';

  @override
  String get upcomingServices => 'Upcoming Services';

  @override
  String get noReminders => 'No service reminders.';

  @override
  String get dueSoon => 'Due Soon';

  @override
  String get upcomingLabel => 'Upcoming';

  @override
  String get laterLabel => 'Later';

  @override
  String get dueAt => 'Due at';

  @override
  String get remaining => 'remaining';

  @override
  String get acknowledgeReminder => 'Acknowledge Reminder';

  @override
  String get acknowledgeReminderMessage =>
      'Mark this service reminder as acknowledged?';

  @override
  String get generateInvoice => 'Generate Invoice';

  @override
  String get generateFromWorkOrder => 'Generate from Work Order';

  @override
  String get invoiceDetail => 'Invoice';

  @override
  String get invoiceSummary => 'Invoice Summary';

  @override
  String get lineItems => 'Line Items';

  @override
  String get labour => 'Labour';

  @override
  String get partsWithMarkup => 'Parts (with markup)';

  @override
  String get partsTotal => 'Parts Total';

  @override
  String get consumables => 'Consumables (5%)';

  @override
  String get editLineItems => 'Edit Line Items';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get subtotalLabel => 'Subtotal';

  @override
  String get ivaLabel => 'IVA (16%)';

  @override
  String get totalDue => 'Total Due';

  @override
  String get exchangeRate => 'Exchange Rate';

  @override
  String get refreshExchangeRate => 'Refresh Exchange Rate';

  @override
  String get invoiceGenerated => 'Invoice generated successfully';

  @override
  String get invoiceSaved => 'Invoice updated.';

  @override
  String get invoiceSent => 'Invoice marked sent.';

  @override
  String get sendInvoice => 'Share Invoice';

  @override
  String get invoiceMarkedPaid => 'Invoice marked as paid.';

  @override
  String get exportPdf => 'Share PDF';

  @override
  String get exportExcel => 'Share Excel';

  @override
  String get downloadPdf => 'Download PDF';

  @override
  String get downloadExcel => 'Download Excel';

  @override
  String get noCompletedWorkOrders => 'No completed work orders to invoice.';

  @override
  String get selectWorkOrderForInvoice => 'Select a completed work order';

  @override
  String get viewInvoice => 'View Invoice';

  @override
  String get addPhotos => 'Add Photos';

  @override
  String get photos => 'Photos';

  @override
  String get gallery => 'Gallery';

  @override
  String get camera => 'Camera';

  @override
  String get uploadingSignature => 'Uploading signature…';

  @override
  String get photoAdded => 'Photo added.';

  @override
  String get photoUploadError => 'Failed to upload photo.';

  @override
  String get serviceReportPhotos => 'Job Photos';

  @override
  String get serviceReportPhotosHint => 'Attach photos taken during the job';

  @override
  String get preDeparture => 'Pre-Departure';

  @override
  String get preTripResults => 'Pre-Trip Checks';

  @override
  String get recentPreTripChecks => 'Recent Pre-Trip Checks';

  @override
  String get noRecentChecks => 'No pre-trip checks on file.';

  @override
  String get checkResult => 'Result';

  @override
  String get liveTelemetry => 'Live Telemetry';

  @override
  String get lastReading => 'Last Reading';

  @override
  String get telemetryHistory => 'Telemetry History';

  @override
  String get noTelemetry => 'No telemetry data available.';

  @override
  String get rpm => 'RPM';

  @override
  String get coolantTemp => 'Coolant (°C)';

  @override
  String get oilPressure => 'Oil (PSI)';

  @override
  String get batteryVoltage => 'Battery (V)';

  @override
  String get throttle => 'Throttle';

  @override
  String get fuelRate => 'Fuel Rate';

  @override
  String get telemetryAlerts => 'Alerts';

  @override
  String get noAlerts => 'No active alerts.';

  @override
  String get acknowledgeAlert => 'Acknowledge';

  @override
  String get alertAcknowledged => 'Alert acknowledged.';

  @override
  String get flaggedIssues => 'Flagged Issues';

  @override
  String get noFlaggedIssues => 'No flagged issues.';

  @override
  String get maintenanceFlags => 'Maintenance Flags';

  @override
  String get noMaintenanceFlags => 'No maintenance flags reported.';

  @override
  String get openIssues => 'Open Issues';

  @override
  String get resolvedIssues => 'Resolved';

  @override
  String get noPreTripChecks => 'No pre-trip checks on file.';

  @override
  String get readings => 'Readings';

  @override
  String get alerts => 'Alerts';

  @override
  String get selectDateRange => 'Select Date Range';

  @override
  String get noTelemetryData => 'No data for selected range.';

  @override
  String get battery => 'Battery (V)';

  @override
  String get boostPressure => 'Boost (PSI)';

  @override
  String get torque => 'Torque';

  @override
  String get engineHours => 'Engine Hours';

  @override
  String get partsInventoryTitle => 'Parts Inventory';

  @override
  String get searchParts => 'Search parts...';

  @override
  String get noInventory => 'No parts in inventory.';

  @override
  String get addInventoryItem => 'Add Part to Inventory';

  @override
  String get editInventoryItem => 'Edit Inventory Item';

  @override
  String get qtyOnHand => 'Qty On Hand';

  @override
  String get minStockLevel => 'Min Stock Level';

  @override
  String get lastUnitCost => 'Last Unit Cost';

  @override
  String get partLocation => 'Location';

  @override
  String get pmPartsTitle => 'Required Parts';

  @override
  String get noPmParts => 'No parts requirements set up.';

  @override
  String get addPmPart => 'Add Required Part';

  @override
  String get editPmPart => 'Edit Required Part';

  @override
  String get partsUnit => 'Unit';

  @override
  String get partsReady => 'Ready';

  @override
  String get partsPartial => 'Partial';

  @override
  String get partsNotReady => 'Not Ready';

  @override
  String partsMissing(int count) {
    return '$count missing';
  }

  @override
  String get partsReadiness => 'Parts Readiness';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get noNotifications => 'No notifications yet.';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get serviceReportListTitle => 'Service Reports';

  @override
  String get noServiceReports => 'No service reports yet.';

  @override
  String get newReport => 'New Report';

  @override
  String get subscriptionTier => 'Subscription Tier';

  @override
  String get upgradeRequired => 'Upgrade Required';

  @override
  String upgradeMessage(String tier) {
    return 'This feature requires a $tier plan. Contact Vórtice to upgrade.';
  }

  @override
  String get gotIt => 'Got it';

  @override
  String get tierFree => 'Free';

  @override
  String get tierManaged => 'Managed';

  @override
  String get tierPlanning => 'Planning';

  @override
  String get tierTelemetry => 'Telemetry';

  @override
  String get tierPredictive => 'Predictive';
}
