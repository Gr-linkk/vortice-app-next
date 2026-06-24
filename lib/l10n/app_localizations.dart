import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// Subtitle shown on the login screen
  ///
  /// In en, this message translates to:
  /// **'Marine & Heavy Equipment Maintenance'**
  String get loginSubtitle;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccount;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get fieldRequired;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get invalidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordTooShort;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get registerTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your organization code to get started.'**
  String get registerSubtitle;

  /// No description provided for @iHaveOrgCode.
  ///
  /// In en, this message translates to:
  /// **'I have an org code'**
  String get iHaveOrgCode;

  /// No description provided for @newClientSignup.
  ///
  /// In en, this message translates to:
  /// **'New client signup'**
  String get newClientSignup;

  /// No description provided for @orgCode.
  ///
  /// In en, this message translates to:
  /// **'Organization Code'**
  String get orgCode;

  /// No description provided for @orgCodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Ask your account manager for this code'**
  String get orgCodeHelper;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @vesselName.
  ///
  /// In en, this message translates to:
  /// **'Vessel Name'**
  String get vesselName;

  /// No description provided for @vesselType.
  ///
  /// In en, this message translates to:
  /// **'Vessel Type'**
  String get vesselType;

  /// No description provided for @marinaLocation.
  ///
  /// In en, this message translates to:
  /// **'Marina / Location'**
  String get marinaLocation;

  /// No description provided for @vesselTypeSailboat.
  ///
  /// In en, this message translates to:
  /// **'Sailboat'**
  String get vesselTypeSailboat;

  /// No description provided for @vesselTypePowerboat.
  ///
  /// In en, this message translates to:
  /// **'Powerboat'**
  String get vesselTypePowerboat;

  /// No description provided for @vesselTypeYacht.
  ///
  /// In en, this message translates to:
  /// **'Yacht'**
  String get vesselTypeYacht;

  /// No description provided for @vesselTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get vesselTypeOther;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @invalidOrgCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid organization code. Please check and try again.'**
  String get invalidOrgCode;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// Greeting on dashboard
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String greeting(String name);

  /// No description provided for @ownerDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get ownerDashboardTitle;

  /// No description provided for @employeeDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'My Work Queue'**
  String get employeeDashboardTitle;

  /// No description provided for @clientDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'My Equipment'**
  String get clientDashboardTitle;

  /// No description provided for @operatorDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Operations'**
  String get operatorDashboardTitle;

  /// No description provided for @clientDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track your fleet and service history.'**
  String get clientDashboardSubtitle;

  /// No description provided for @operatorDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start your daily checklist or report an issue.'**
  String get operatorDashboardSubtitle;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navAssets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get navAssets;

  /// No description provided for @navWorkOrders.
  ///
  /// In en, this message translates to:
  /// **'Work Orders'**
  String get navWorkOrders;

  /// No description provided for @navServiceReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navServiceReports;

  /// No description provided for @navParts.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get navParts;

  /// No description provided for @navInvoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get navInvoices;

  /// No description provided for @navChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get navChecklist;

  /// No description provided for @navFlags.
  ///
  /// In en, this message translates to:
  /// **'Flags'**
  String get navFlags;

  /// No description provided for @totalAssets.
  ///
  /// In en, this message translates to:
  /// **'Total Assets'**
  String get totalAssets;

  /// No description provided for @openWorkOrders.
  ///
  /// In en, this message translates to:
  /// **'Open Orders'**
  String get openWorkOrders;

  /// No description provided for @recentWorkOrders.
  ///
  /// In en, this message translates to:
  /// **'Recent Work Orders'**
  String get recentWorkOrders;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @noWorkOrders.
  ///
  /// In en, this message translates to:
  /// **'No work orders found.'**
  String get noWorkOrders;

  /// No description provided for @assignedToMe.
  ///
  /// In en, this message translates to:
  /// **'Assigned to Me'**
  String get assignedToMe;

  /// No description provided for @noAssignedWorkOrders.
  ///
  /// In en, this message translates to:
  /// **'No active work orders assigned to you.'**
  String get noAssignedWorkOrders;

  /// No description provided for @myFleet.
  ///
  /// In en, this message translates to:
  /// **'My Fleet'**
  String get myFleet;

  /// No description provided for @noAssets.
  ///
  /// In en, this message translates to:
  /// **'No assets found.'**
  String get noAssets;

  /// No description provided for @availableAssets.
  ///
  /// In en, this message translates to:
  /// **'Available Assets'**
  String get availableAssets;

  /// No description provided for @activeServices.
  ///
  /// In en, this message translates to:
  /// **'Active Services'**
  String get activeServices;

  /// No description provided for @assetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assetsTitle;

  /// No description provided for @assetType.
  ///
  /// In en, this message translates to:
  /// **'Asset Type'**
  String get assetType;

  /// No description provided for @searchAssets.
  ///
  /// In en, this message translates to:
  /// **'Search assets...'**
  String get searchAssets;

  /// No description provided for @addAsset.
  ///
  /// In en, this message translates to:
  /// **'Add Asset'**
  String get addAsset;

  /// No description provided for @saveAsset.
  ///
  /// In en, this message translates to:
  /// **'Save Asset'**
  String get saveAsset;

  /// No description provided for @assetDetail.
  ///
  /// In en, this message translates to:
  /// **'Asset Detail'**
  String get assetDetail;

  /// No description provided for @assetDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get assetDetails;

  /// No description provided for @assetName.
  ///
  /// In en, this message translates to:
  /// **'Asset Name'**
  String get assetName;

  /// No description provided for @serialNumber.
  ///
  /// In en, this message translates to:
  /// **'Serial Number'**
  String get serialNumber;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @manufacturer.
  ///
  /// In en, this message translates to:
  /// **'Manufacturer'**
  String get manufacturer;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @assetNotFound.
  ///
  /// In en, this message translates to:
  /// **'Asset not found.'**
  String get assetNotFound;

  /// No description provided for @invalidYear.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid year'**
  String get invalidYear;

  /// No description provided for @editAsset.
  ///
  /// In en, this message translates to:
  /// **'Edit Asset'**
  String get editAsset;

  /// No description provided for @addEngineHint.
  ///
  /// In en, this message translates to:
  /// **'Add the primary engine (you can add more later)'**
  String get addEngineHint;

  /// No description provided for @reassignTech.
  ///
  /// In en, this message translates to:
  /// **'Reassign Tech'**
  String get reassignTech;

  /// No description provided for @srComplaint.
  ///
  /// In en, this message translates to:
  /// **'1 — Complaint'**
  String get srComplaint;

  /// No description provided for @srComplaintSub.
  ///
  /// In en, this message translates to:
  /// **'Client\'s reported issue in their words'**
  String get srComplaintSub;

  /// No description provided for @srCause.
  ///
  /// In en, this message translates to:
  /// **'2 — Cause'**
  String get srCause;

  /// No description provided for @srCauseSub.
  ///
  /// In en, this message translates to:
  /// **'Diagnosed root cause of the problem'**
  String get srCauseSub;

  /// No description provided for @srCorrection.
  ///
  /// In en, this message translates to:
  /// **'3 — Correction'**
  String get srCorrection;

  /// No description provided for @srCorrectionSub.
  ///
  /// In en, this message translates to:
  /// **'Work performed and parts replaced'**
  String get srCorrectionSub;

  /// No description provided for @srSecondaryDamage.
  ///
  /// In en, this message translates to:
  /// **'4 — Contingent Damage'**
  String get srSecondaryDamage;

  /// No description provided for @srSecondaryDamageSub.
  ///
  /// In en, this message translates to:
  /// **'Contingent damage caused by or discovered during this job'**
  String get srSecondaryDamageSub;

  /// No description provided for @srComments.
  ///
  /// In en, this message translates to:
  /// **'5 — Comments'**
  String get srComments;

  /// No description provided for @srCommentsSub.
  ///
  /// In en, this message translates to:
  /// **'Recommendations, next service, items to watch'**
  String get srCommentsSub;

  /// No description provided for @srComplaintHint.
  ///
  /// In en, this message translates to:
  /// **'What did the client report?'**
  String get srComplaintHint;

  /// No description provided for @srCauseHint.
  ///
  /// In en, this message translates to:
  /// **'What caused the issue?'**
  String get srCauseHint;

  /// No description provided for @srCorrectionHint.
  ///
  /// In en, this message translates to:
  /// **'What work was done? What was replaced?'**
  String get srCorrectionHint;

  /// No description provided for @srSecondaryDamageHint.
  ///
  /// In en, this message translates to:
  /// **'Contingent damage caused by the primary work or findings outside the main scope'**
  String get srSecondaryDamageHint;

  /// No description provided for @srCommentsHint.
  ///
  /// In en, this message translates to:
  /// **'Anything the client should know or watch for'**
  String get srCommentsHint;

  /// No description provided for @workOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Work Orders'**
  String get workOrdersTitle;

  /// No description provided for @workOrderDetail.
  ///
  /// In en, this message translates to:
  /// **'Work Order'**
  String get workOrderDetail;

  /// No description provided for @workOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get workOrderTitle;

  /// No description provided for @createWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Create Work Order'**
  String get createWorkOrder;

  /// No description provided for @linkedAsset.
  ///
  /// In en, this message translates to:
  /// **'Linked Asset'**
  String get linkedAsset;

  /// No description provided for @noAsset.
  ///
  /// In en, this message translates to:
  /// **'No asset'**
  String get noAsset;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @jobType.
  ///
  /// In en, this message translates to:
  /// **'Job Type'**
  String get jobType;

  /// No description provided for @scheduledDate.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Date'**
  String get scheduledDate;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get dueDate;

  /// No description provided for @completedAt.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completedAt;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select a date'**
  String get selectDate;

  /// No description provided for @startWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Start Work Order'**
  String get startWorkOrder;

  /// No description provided for @reopenWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Reopen Work Order'**
  String get reopenWorkOrder;

  /// No description provided for @completeWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Mark Completed'**
  String get completeWorkOrder;

  /// No description provided for @statusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get statusOpen;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get statusInProgress;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @viewChecklist.
  ///
  /// In en, this message translates to:
  /// **'View Checklist'**
  String get viewChecklist;

  /// No description provided for @serviceReport.
  ///
  /// In en, this message translates to:
  /// **'Service Report'**
  String get serviceReport;

  /// No description provided for @selectWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Please select a work order'**
  String get selectWorkOrder;

  /// No description provided for @linkedWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Linked Work Order'**
  String get linkedWorkOrder;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found.'**
  String get notFound;

  /// No description provided for @woDetailsSection.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get woDetailsSection;

  /// No description provided for @assignedTech.
  ///
  /// In en, this message translates to:
  /// **'Assigned Tech'**
  String get assignedTech;

  /// No description provided for @hoursAtStart.
  ///
  /// In en, this message translates to:
  /// **'Engine Hours (Start)'**
  String get hoursAtStart;

  /// No description provided for @hoursAtEnd.
  ///
  /// In en, this message translates to:
  /// **'Engine Hours (End)'**
  String get hoursAtEnd;

  /// No description provided for @labourHours.
  ///
  /// In en, this message translates to:
  /// **'Labour Hours'**
  String get labourHours;

  /// No description provided for @billableRate.
  ///
  /// In en, this message translates to:
  /// **'Billable Rate'**
  String get billableRate;

  /// No description provided for @wageRate.
  ///
  /// In en, this message translates to:
  /// **'Wage Rate'**
  String get wageRate;

  /// No description provided for @internalNotes.
  ///
  /// In en, this message translates to:
  /// **'Internal Notes'**
  String get internalNotes;

  /// No description provided for @onHoldReason.
  ///
  /// In en, this message translates to:
  /// **'On-Hold Reason'**
  String get onHoldReason;

  /// No description provided for @editWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Edit Work Order'**
  String get editWorkOrder;

  /// No description provided for @checklistTitle.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get checklistTitle;

  /// No description provided for @selectTemplate.
  ///
  /// In en, this message translates to:
  /// **'Select Template'**
  String get selectTemplate;

  /// No description provided for @noChecklistTemplates.
  ///
  /// In en, this message translates to:
  /// **'No checklist templates available.'**
  String get noChecklistTemplates;

  /// No description provided for @checklistSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Checklist submitted successfully.'**
  String get checklistSubmitted;

  /// No description provided for @submitChecklist.
  ///
  /// In en, this message translates to:
  /// **'Submit Checklist'**
  String get submitChecklist;

  /// No description provided for @completeChecklist.
  ///
  /// In en, this message translates to:
  /// **'Complete Checklist'**
  String get completeChecklist;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @startChecklist.
  ///
  /// In en, this message translates to:
  /// **'Start Checklist'**
  String get startChecklist;

  /// No description provided for @serviceReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Service Report'**
  String get serviceReportTitle;

  /// No description provided for @technicianNotes.
  ///
  /// In en, this message translates to:
  /// **'Technician Notes'**
  String get technicianNotes;

  /// No description provided for @hoursWorked.
  ///
  /// In en, this message translates to:
  /// **'Hours Worked'**
  String get hoursWorked;

  /// No description provided for @technicianSignature.
  ///
  /// In en, this message translates to:
  /// **'Technician Signature'**
  String get technicianSignature;

  /// No description provided for @signHere.
  ///
  /// In en, this message translates to:
  /// **'Sign here'**
  String get signHere;

  /// No description provided for @clearSignature.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearSignature;

  /// No description provided for @saveSignature.
  ///
  /// In en, this message translates to:
  /// **'Save Signature'**
  String get saveSignature;

  /// No description provided for @signatureSaved.
  ///
  /// In en, this message translates to:
  /// **'Signature saved.'**
  String get signatureSaved;

  /// No description provided for @signatureCaptured.
  ///
  /// In en, this message translates to:
  /// **'Signature captured'**
  String get signatureCaptured;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReport;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted successfully.'**
  String get reportSubmitted;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid number'**
  String get invalidNumber;

  /// No description provided for @partsTitle.
  ///
  /// In en, this message translates to:
  /// **'Parts Log'**
  String get partsTitle;

  /// No description provided for @partName.
  ///
  /// In en, this message translates to:
  /// **'Part Name'**
  String get partName;

  /// No description provided for @partNumber.
  ///
  /// In en, this message translates to:
  /// **'Part Number'**
  String get partNumber;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get quantity;

  /// No description provided for @unitCost.
  ///
  /// In en, this message translates to:
  /// **'Unit Cost'**
  String get unitCost;

  /// No description provided for @supplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get supplier;

  /// No description provided for @addPart.
  ///
  /// In en, this message translates to:
  /// **'Add Part'**
  String get addPart;

  /// No description provided for @noParts.
  ///
  /// In en, this message translates to:
  /// **'No parts logged.'**
  String get noParts;

  /// No description provided for @invoicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get invoicesTitle;

  /// No description provided for @invoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice #'**
  String get invoiceNumber;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @unpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get unpaid;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @markPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark Paid'**
  String get markPaid;

  /// No description provided for @noInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices found.'**
  String get noInvoices;

  /// No description provided for @operatorChecklistTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Checklist'**
  String get operatorChecklistTitle;

  /// No description provided for @selectAsset.
  ///
  /// In en, this message translates to:
  /// **'Select Asset'**
  String get selectAsset;

  /// No description provided for @maintenanceFlagTitle.
  ///
  /// In en, this message translates to:
  /// **'Flag for Maintenance'**
  String get maintenanceFlagTitle;

  /// No description provided for @flagInfo.
  ///
  /// In en, this message translates to:
  /// **'Flagged issues are sent directly to the maintenance team.'**
  String get flagInfo;

  /// No description provided for @issueDescription.
  ///
  /// In en, this message translates to:
  /// **'Describe the issue'**
  String get issueDescription;

  /// No description provided for @flagIssue.
  ///
  /// In en, this message translates to:
  /// **'Flag Issue'**
  String get flagIssue;

  /// No description provided for @flagSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Issue flagged successfully.'**
  String get flagSubmitted;

  /// No description provided for @submitFlag.
  ///
  /// In en, this message translates to:
  /// **'Submit Flag'**
  String get submitFlag;

  /// No description provided for @priorityLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get priorityLow;

  /// No description provided for @priorityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get priorityMedium;

  /// No description provided for @priorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get priorityHigh;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get confirmDeleteMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get spanish;

  /// No description provided for @enginesTitle.
  ///
  /// In en, this message translates to:
  /// **'Engines'**
  String get enginesTitle;

  /// No description provided for @noEngines.
  ///
  /// In en, this message translates to:
  /// **'No engines found.'**
  String get noEngines;

  /// No description provided for @addEngine.
  ///
  /// In en, this message translates to:
  /// **'Add Engine'**
  String get addEngine;

  /// No description provided for @editEngine.
  ///
  /// In en, this message translates to:
  /// **'Edit Engine'**
  String get editEngine;

  /// No description provided for @engineLabel.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get engineLabel;

  /// No description provided for @engineKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get engineKind;

  /// No description provided for @currentHours.
  ///
  /// In en, this message translates to:
  /// **'Current Hours'**
  String get currentHours;

  /// No description provided for @enginesCount.
  ///
  /// In en, this message translates to:
  /// **'engines'**
  String get enginesCount;

  /// No description provided for @hourLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Hour Log'**
  String get hourLogsTitle;

  /// No description provided for @noHourLogs.
  ///
  /// In en, this message translates to:
  /// **'No hour entries logged.'**
  String get noHourLogs;

  /// No description provided for @logHours.
  ///
  /// In en, this message translates to:
  /// **'Log Hours'**
  String get logHours;

  /// No description provided for @clientsTitle.
  ///
  /// In en, this message translates to:
  /// **'Clients'**
  String get clientsTitle;

  /// No description provided for @searchClients.
  ///
  /// In en, this message translates to:
  /// **'Search clients...'**
  String get searchClients;

  /// No description provided for @noClients.
  ///
  /// In en, this message translates to:
  /// **'No clients found.'**
  String get noClients;

  /// No description provided for @clientDetails.
  ///
  /// In en, this message translates to:
  /// **'Client Details'**
  String get clientDetails;

  /// No description provided for @orgCodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Org Codes'**
  String get orgCodesTitle;

  /// No description provided for @noOrgCodes.
  ///
  /// In en, this message translates to:
  /// **'No org codes found.'**
  String get noOrgCodes;

  /// No description provided for @createOrgCode.
  ///
  /// In en, this message translates to:
  /// **'Create Org Code'**
  String get createOrgCode;

  /// No description provided for @intendedRole.
  ///
  /// In en, this message translates to:
  /// **'Intended Role'**
  String get intendedRole;

  /// No description provided for @maxUses.
  ///
  /// In en, this message translates to:
  /// **'Max Uses'**
  String get maxUses;

  /// No description provided for @singleUse.
  ///
  /// In en, this message translates to:
  /// **'Single Use'**
  String get singleUse;

  /// No description provided for @expirationDate.
  ///
  /// In en, this message translates to:
  /// **'Expiration Date (optional)'**
  String get expirationDate;

  /// No description provided for @upcomingServices.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Services'**
  String get upcomingServices;

  /// No description provided for @noReminders.
  ///
  /// In en, this message translates to:
  /// **'No service reminders.'**
  String get noReminders;

  /// No description provided for @dueSoon.
  ///
  /// In en, this message translates to:
  /// **'Due Soon'**
  String get dueSoon;

  /// No description provided for @upcomingLabel.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcomingLabel;

  /// No description provided for @laterLabel.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get laterLabel;

  /// No description provided for @dueAt.
  ///
  /// In en, this message translates to:
  /// **'Due at'**
  String get dueAt;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'remaining'**
  String get remaining;

  /// No description provided for @acknowledgeReminder.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge Reminder'**
  String get acknowledgeReminder;

  /// No description provided for @acknowledgeReminderMessage.
  ///
  /// In en, this message translates to:
  /// **'Mark this service reminder as acknowledged?'**
  String get acknowledgeReminderMessage;

  /// No description provided for @generateInvoice.
  ///
  /// In en, this message translates to:
  /// **'Generate Invoice'**
  String get generateInvoice;

  /// No description provided for @generateFromWorkOrder.
  ///
  /// In en, this message translates to:
  /// **'Generate from Work Order'**
  String get generateFromWorkOrder;

  /// No description provided for @invoiceDetail.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoiceDetail;

  /// No description provided for @invoiceSummary.
  ///
  /// In en, this message translates to:
  /// **'Invoice Summary'**
  String get invoiceSummary;

  /// No description provided for @lineItems.
  ///
  /// In en, this message translates to:
  /// **'Line Items'**
  String get lineItems;

  /// No description provided for @labour.
  ///
  /// In en, this message translates to:
  /// **'Labour'**
  String get labour;

  /// No description provided for @partsWithMarkup.
  ///
  /// In en, this message translates to:
  /// **'Parts (with markup)'**
  String get partsWithMarkup;

  /// No description provided for @partsTotal.
  ///
  /// In en, this message translates to:
  /// **'Parts Total'**
  String get partsTotal;

  /// No description provided for @consumables.
  ///
  /// In en, this message translates to:
  /// **'Consumables (5%)'**
  String get consumables;

  /// No description provided for @editLineItems.
  ///
  /// In en, this message translates to:
  /// **'Edit Line Items'**
  String get editLineItems;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @subtotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotalLabel;

  /// No description provided for @ivaLabel.
  ///
  /// In en, this message translates to:
  /// **'IVA (16%)'**
  String get ivaLabel;

  /// No description provided for @totalDue.
  ///
  /// In en, this message translates to:
  /// **'Total Due'**
  String get totalDue;

  /// No description provided for @exchangeRate.
  ///
  /// In en, this message translates to:
  /// **'Exchange Rate'**
  String get exchangeRate;

  /// No description provided for @refreshExchangeRate.
  ///
  /// In en, this message translates to:
  /// **'Refresh Exchange Rate'**
  String get refreshExchangeRate;

  /// No description provided for @invoiceGenerated.
  ///
  /// In en, this message translates to:
  /// **'Invoice generated successfully'**
  String get invoiceGenerated;

  /// No description provided for @invoiceSaved.
  ///
  /// In en, this message translates to:
  /// **'Invoice updated.'**
  String get invoiceSaved;

  /// No description provided for @invoiceSent.
  ///
  /// In en, this message translates to:
  /// **'Invoice marked sent.'**
  String get invoiceSent;

  /// No description provided for @sendInvoice.
  ///
  /// In en, this message translates to:
  /// **'Share Invoice'**
  String get sendInvoice;

  /// No description provided for @invoiceMarkedPaid.
  ///
  /// In en, this message translates to:
  /// **'Invoice marked as paid.'**
  String get invoiceMarkedPaid;

  /// No description provided for @exportPdf.
  ///
  /// In en, this message translates to:
  /// **'Share PDF'**
  String get exportPdf;

  /// No description provided for @exportExcel.
  ///
  /// In en, this message translates to:
  /// **'Share Excel'**
  String get exportExcel;

  /// No description provided for @downloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get downloadPdf;

  /// No description provided for @downloadExcel.
  ///
  /// In en, this message translates to:
  /// **'Download Excel'**
  String get downloadExcel;

  /// No description provided for @noCompletedWorkOrders.
  ///
  /// In en, this message translates to:
  /// **'No completed work orders to invoice.'**
  String get noCompletedWorkOrders;

  /// No description provided for @selectWorkOrderForInvoice.
  ///
  /// In en, this message translates to:
  /// **'Select a completed work order'**
  String get selectWorkOrderForInvoice;

  /// No description provided for @viewInvoice.
  ///
  /// In en, this message translates to:
  /// **'View Invoice'**
  String get viewInvoice;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add Photos'**
  String get addPhotos;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @uploadingSignature.
  ///
  /// In en, this message translates to:
  /// **'Uploading signature…'**
  String get uploadingSignature;

  /// No description provided for @photoAdded.
  ///
  /// In en, this message translates to:
  /// **'Photo added.'**
  String get photoAdded;

  /// No description provided for @photoUploadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload photo.'**
  String get photoUploadError;

  /// No description provided for @serviceReportPhotos.
  ///
  /// In en, this message translates to:
  /// **'Job Photos'**
  String get serviceReportPhotos;

  /// No description provided for @serviceReportPhotosHint.
  ///
  /// In en, this message translates to:
  /// **'Attach photos taken during the job'**
  String get serviceReportPhotosHint;

  /// No description provided for @preDeparture.
  ///
  /// In en, this message translates to:
  /// **'Pre-Departure'**
  String get preDeparture;

  /// No description provided for @preTripResults.
  ///
  /// In en, this message translates to:
  /// **'Pre-Trip Checks'**
  String get preTripResults;

  /// No description provided for @recentPreTripChecks.
  ///
  /// In en, this message translates to:
  /// **'Recent Pre-Trip Checks'**
  String get recentPreTripChecks;

  /// No description provided for @noRecentChecks.
  ///
  /// In en, this message translates to:
  /// **'No pre-trip checks on file.'**
  String get noRecentChecks;

  /// No description provided for @checkResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get checkResult;

  /// No description provided for @liveTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Live Telemetry'**
  String get liveTelemetry;

  /// No description provided for @lastReading.
  ///
  /// In en, this message translates to:
  /// **'Last Reading'**
  String get lastReading;

  /// No description provided for @telemetryHistory.
  ///
  /// In en, this message translates to:
  /// **'Telemetry History'**
  String get telemetryHistory;

  /// No description provided for @noTelemetry.
  ///
  /// In en, this message translates to:
  /// **'No telemetry data available.'**
  String get noTelemetry;

  /// No description provided for @rpm.
  ///
  /// In en, this message translates to:
  /// **'RPM'**
  String get rpm;

  /// No description provided for @coolantTemp.
  ///
  /// In en, this message translates to:
  /// **'Coolant (°C)'**
  String get coolantTemp;

  /// No description provided for @oilPressure.
  ///
  /// In en, this message translates to:
  /// **'Oil (PSI)'**
  String get oilPressure;

  /// No description provided for @batteryVoltage.
  ///
  /// In en, this message translates to:
  /// **'Battery (V)'**
  String get batteryVoltage;

  /// No description provided for @throttle.
  ///
  /// In en, this message translates to:
  /// **'Throttle'**
  String get throttle;

  /// No description provided for @fuelRate.
  ///
  /// In en, this message translates to:
  /// **'Fuel Rate'**
  String get fuelRate;

  /// No description provided for @telemetryAlerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get telemetryAlerts;

  /// No description provided for @noAlerts.
  ///
  /// In en, this message translates to:
  /// **'No active alerts.'**
  String get noAlerts;

  /// No description provided for @acknowledgeAlert.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge'**
  String get acknowledgeAlert;

  /// No description provided for @alertAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'Alert acknowledged.'**
  String get alertAcknowledged;

  /// No description provided for @flaggedIssues.
  ///
  /// In en, this message translates to:
  /// **'Flagged Issues'**
  String get flaggedIssues;

  /// No description provided for @noFlaggedIssues.
  ///
  /// In en, this message translates to:
  /// **'No flagged issues.'**
  String get noFlaggedIssues;

  /// No description provided for @maintenanceFlags.
  ///
  /// In en, this message translates to:
  /// **'Maintenance Flags'**
  String get maintenanceFlags;

  /// No description provided for @noMaintenanceFlags.
  ///
  /// In en, this message translates to:
  /// **'No maintenance flags reported.'**
  String get noMaintenanceFlags;

  /// No description provided for @openIssues.
  ///
  /// In en, this message translates to:
  /// **'Open Issues'**
  String get openIssues;

  /// No description provided for @resolvedIssues.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get resolvedIssues;

  /// No description provided for @noPreTripChecks.
  ///
  /// In en, this message translates to:
  /// **'No pre-trip checks on file.'**
  String get noPreTripChecks;

  /// No description provided for @readings.
  ///
  /// In en, this message translates to:
  /// **'Readings'**
  String get readings;

  /// No description provided for @alerts.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alerts;

  /// No description provided for @selectDateRange.
  ///
  /// In en, this message translates to:
  /// **'Select Date Range'**
  String get selectDateRange;

  /// No description provided for @noTelemetryData.
  ///
  /// In en, this message translates to:
  /// **'No data for selected range.'**
  String get noTelemetryData;

  /// No description provided for @battery.
  ///
  /// In en, this message translates to:
  /// **'Battery (V)'**
  String get battery;

  /// No description provided for @boostPressure.
  ///
  /// In en, this message translates to:
  /// **'Boost (PSI)'**
  String get boostPressure;

  /// No description provided for @torque.
  ///
  /// In en, this message translates to:
  /// **'Torque'**
  String get torque;

  /// No description provided for @engineHours.
  ///
  /// In en, this message translates to:
  /// **'Engine Hours'**
  String get engineHours;

  /// No description provided for @partsInventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Parts Inventory'**
  String get partsInventoryTitle;

  /// No description provided for @searchParts.
  ///
  /// In en, this message translates to:
  /// **'Search parts...'**
  String get searchParts;

  /// No description provided for @noInventory.
  ///
  /// In en, this message translates to:
  /// **'No parts in inventory.'**
  String get noInventory;

  /// No description provided for @addInventoryItem.
  ///
  /// In en, this message translates to:
  /// **'Add Part to Inventory'**
  String get addInventoryItem;

  /// No description provided for @editInventoryItem.
  ///
  /// In en, this message translates to:
  /// **'Edit Inventory Item'**
  String get editInventoryItem;

  /// No description provided for @qtyOnHand.
  ///
  /// In en, this message translates to:
  /// **'Qty On Hand'**
  String get qtyOnHand;

  /// No description provided for @minStockLevel.
  ///
  /// In en, this message translates to:
  /// **'Min Stock Level'**
  String get minStockLevel;

  /// No description provided for @lastUnitCost.
  ///
  /// In en, this message translates to:
  /// **'Last Unit Cost'**
  String get lastUnitCost;

  /// No description provided for @partLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get partLocation;

  /// No description provided for @pmPartsTitle.
  ///
  /// In en, this message translates to:
  /// **'Required Parts'**
  String get pmPartsTitle;

  /// No description provided for @noPmParts.
  ///
  /// In en, this message translates to:
  /// **'No parts requirements set up.'**
  String get noPmParts;

  /// No description provided for @addPmPart.
  ///
  /// In en, this message translates to:
  /// **'Add Required Part'**
  String get addPmPart;

  /// No description provided for @editPmPart.
  ///
  /// In en, this message translates to:
  /// **'Edit Required Part'**
  String get editPmPart;

  /// No description provided for @partsUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get partsUnit;

  /// No description provided for @partsReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get partsReady;

  /// No description provided for @partsPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get partsPartial;

  /// No description provided for @partsNotReady.
  ///
  /// In en, this message translates to:
  /// **'Not Ready'**
  String get partsNotReady;

  /// No description provided for @partsMissing.
  ///
  /// In en, this message translates to:
  /// **'{count} missing'**
  String partsMissing(int count);

  /// No description provided for @partsReadiness.
  ///
  /// In en, this message translates to:
  /// **'Parts Readiness'**
  String get partsReadiness;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get noNotifications;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @serviceReportListTitle.
  ///
  /// In en, this message translates to:
  /// **'Service Reports'**
  String get serviceReportListTitle;

  /// No description provided for @noServiceReports.
  ///
  /// In en, this message translates to:
  /// **'No service reports yet.'**
  String get noServiceReports;

  /// No description provided for @newReport.
  ///
  /// In en, this message translates to:
  /// **'New Report'**
  String get newReport;

  /// No description provided for @subscriptionTier.
  ///
  /// In en, this message translates to:
  /// **'Subscription Tier'**
  String get subscriptionTier;

  /// No description provided for @upgradeRequired.
  ///
  /// In en, this message translates to:
  /// **'Upgrade Required'**
  String get upgradeRequired;

  /// No description provided for @upgradeMessage.
  ///
  /// In en, this message translates to:
  /// **'This feature requires a {tier} plan. Contact Vórtice to upgrade.'**
  String upgradeMessage(String tier);

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @tierFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get tierFree;

  /// No description provided for @tierManaged.
  ///
  /// In en, this message translates to:
  /// **'Managed'**
  String get tierManaged;

  /// No description provided for @tierPlanning.
  ///
  /// In en, this message translates to:
  /// **'Planning'**
  String get tierPlanning;

  /// No description provided for @tierTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Telemetry'**
  String get tierTelemetry;

  /// No description provided for @tierPredictive.
  ///
  /// In en, this message translates to:
  /// **'Predictive'**
  String get tierPredictive;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
