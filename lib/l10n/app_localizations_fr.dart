// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get loginSubtitle => 'Entretien de matériel maritime et lourd';

  @override
  String get email => 'Courriel';

  @override
  String get password => 'Mot de passe';

  @override
  String get signIn => 'Se connecter';

  @override
  String get forgotPassword => 'Mot de passe oublié ?';

  @override
  String get noAccount => 'Vous n’avez pas de compte ?';

  @override
  String get register => 'S’inscrire';

  @override
  String get fieldRequired => 'Ce champ est obligatoire';

  @override
  String get invalidEmail => 'Saisissez une adresse courriel valide';

  @override
  String get passwordTooShort =>
      'Le mot de passe doit contenir au moins 6 caractères';

  @override
  String get registerTitle => 'Créer un compte';

  @override
  String get registerSubtitle =>
      'Saisissez le code de votre organisation pour commencer.';

  @override
  String get iHaveOrgCode => 'J’ai un code d’organisation';

  @override
  String get newClientSignup => 'Inscription d’un nouveau client';

  @override
  String get orgCode => 'Code d’organisation';

  @override
  String get orgCodeHelper =>
      'Demandez ce code à la personne responsable de votre compte';

  @override
  String get fullName => 'Nom complet';

  @override
  String get phone => 'Téléphone';

  @override
  String get vesselName => 'Nom du bateau';

  @override
  String get vesselType => 'Type de bateau';

  @override
  String get marinaLocation => 'Marina / Emplacement';

  @override
  String get vesselTypeSailboat => 'Voilier';

  @override
  String get vesselTypePowerboat => 'Bateau à moteur';

  @override
  String get vesselTypeYacht => 'Yacht';

  @override
  String get vesselTypeOther => 'Autre';

  @override
  String get confirmPassword => 'Confirmer le mot de passe';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get invalidOrgCode =>
      'Code d’organisation invalide. Vérifiez-le et réessayez.';

  @override
  String get createAccount => 'Créer le compte';

  @override
  String get alreadyHaveAccount => 'Vous avez déjà un compte ?';

  @override
  String greeting(String name) {
    return 'Bonjour, $name';
  }

  @override
  String get ownerDashboardTitle => 'Tableau de bord';

  @override
  String get employeeDashboardTitle => 'Ma file de travail';

  @override
  String get clientDashboardTitle => 'Mon équipement';

  @override
  String get operatorDashboardTitle => 'Opérations quotidiennes';

  @override
  String get clientDashboardSubtitle =>
      'Suivez votre parc et l’historique des interventions.';

  @override
  String get operatorDashboardSubtitle =>
      'Commencez votre inspection quotidienne ou signalez un problème.';

  @override
  String get navDashboard => 'Tableau de bord';

  @override
  String get navAssets => 'Équipements';

  @override
  String get navWorkOrders => 'Bons de travail';

  @override
  String get navServiceReports => 'Rapports';

  @override
  String get navParts => 'Pièces';

  @override
  String get navInvoices => 'Factures';

  @override
  String get navChecklist => 'Liste de contrôle';

  @override
  String get navFlags => 'Signalements';

  @override
  String get totalAssets => 'Nombre total d’équipements';

  @override
  String get openWorkOrders => 'Ordres ouverts';

  @override
  String get recentWorkOrders => 'Bons de travail récents';

  @override
  String get viewAll => 'Tout afficher';

  @override
  String get noWorkOrders => 'Aucun bon de travail trouvé.';

  @override
  String get assignedToMe => 'Bons de travail qui me sont attribués';

  @override
  String get noAssignedWorkOrders =>
      'Aucun bon de travail actif ne vous est attribué.';

  @override
  String get myFleet => 'Mon parc';

  @override
  String get noAssets => 'Aucun équipement trouvé.';

  @override
  String get availableAssets => 'Équipements disponibles';

  @override
  String get activeServices => 'Interventions en cours';

  @override
  String get assetsTitle => 'Équipements';

  @override
  String get assetType => 'Type d’équipement';

  @override
  String get searchAssets => 'Rechercher des équipements…';

  @override
  String get addAsset => 'Ajouter un équipement';

  @override
  String get saveAsset => 'Enregistrer l’équipement';

  @override
  String get assetDetail => 'Détail de l’équipement';

  @override
  String get assetDetails => 'Détails';

  @override
  String get assetName => 'Nom de l’équipement';

  @override
  String get serialNumber => 'Numéro de série';

  @override
  String get model => 'Modèle';

  @override
  String get manufacturer => 'Fabricant';

  @override
  String get year => 'Année';

  @override
  String get location => 'Emplacement';

  @override
  String get status => 'État';

  @override
  String get notes => 'Notes';

  @override
  String get assetNotFound => 'Équipement introuvable.';

  @override
  String get invalidYear => 'Saisissez une année valide';

  @override
  String get editAsset => 'Modifier l’équipement';

  @override
  String get addEngineHint =>
      'Ajoutez le moteur principal (vous pourrez en ajouter d’autres plus tard)';

  @override
  String get reassignTech => 'Réattribuer le technicien';

  @override
  String get srComplaint => '1 — Problème signalé';

  @override
  String get srComplaintSub =>
      'Le problème décrit par le client, avec ses mots';

  @override
  String get srCause => '2 — Cause';

  @override
  String get srCauseSub => 'Cause fondamentale diagnostiquée';

  @override
  String get srCorrection => '3 — Correction';

  @override
  String get srCorrectionSub => 'Travaux effectués et pièces remplacées';

  @override
  String get srSecondaryDamage => '4 — Dommages connexes';

  @override
  String get srSecondaryDamageSub =>
      'Dommages connexes causés ou découverts pendant ce travail';

  @override
  String get srComments => '5 — Commentaires';

  @override
  String get srCommentsSub =>
      'Recommandations, prochaine intervention et éléments à surveiller';

  @override
  String get srComplaintHint => 'Quel problème le client a-t-il signalé ?';

  @override
  String get srCauseHint => 'Quelle est la cause du problème ?';

  @override
  String get srCorrectionHint =>
      'Quels travaux ont été effectués ? Quelles pièces ont été remplacées ?';

  @override
  String get srSecondaryDamageHint =>
      'Dommages connexes causés par les travaux principaux ou constatés hors de leur portée';

  @override
  String get srCommentsHint =>
      'Que devrait savoir le client ou que devrait-il surveiller ?';

  @override
  String get workOrdersTitle => 'Bons de travail';

  @override
  String get workOrderDetail => 'Bon de travail';

  @override
  String get workOrderTitle => 'Titre';

  @override
  String get createWorkOrder => 'Créer un bon de travail';

  @override
  String get linkedAsset => 'Équipement associé';

  @override
  String get noAsset => 'Aucun équipement';

  @override
  String get description => 'Description';

  @override
  String get jobType => 'Type de travail';

  @override
  String get scheduledDate => 'Date prévue';

  @override
  String get priority => 'Priorité';

  @override
  String get dueDate => 'Date d’échéance';

  @override
  String get completedAt => 'Terminé';

  @override
  String get selectDate => 'Choisir une date';

  @override
  String get startWorkOrder => 'Commencer le travail';

  @override
  String get reopenWorkOrder => 'Rouvrir le bon de travail';

  @override
  String get completeWorkOrder => 'Marquer comme terminé';

  @override
  String get statusOpen => 'Ouvert';

  @override
  String get statusInProgress => 'En cours';

  @override
  String get statusCompleted => 'Terminé';

  @override
  String get actions => 'Actions';

  @override
  String get viewChecklist => 'Voir la liste de contrôle';

  @override
  String get serviceReport => 'Rapport d’intervention';

  @override
  String get selectWorkOrder => 'Veuillez choisir un bon de travail';

  @override
  String get linkedWorkOrder => 'Bon de travail associé';

  @override
  String get notFound => 'Introuvable.';

  @override
  String get woDetailsSection => 'Détails';

  @override
  String get assignedTech => 'Technicien assigné';

  @override
  String get hoursAtStart => 'Heures moteur au début';

  @override
  String get hoursAtEnd => 'Heures moteur à la fin';

  @override
  String get labourHours => 'Heures de main-d’œuvre';

  @override
  String get billableRate => 'Taux facturable';

  @override
  String get wageRate => 'Taux horaire';

  @override
  String get internalNotes => 'Notes internes';

  @override
  String get onHoldReason => 'Motif de mise en attente';

  @override
  String get editWorkOrder => 'Modifier le bon de travail';

  @override
  String get checklistTitle => 'Liste de contrôle';

  @override
  String get selectTemplate => 'Choisir un modèle';

  @override
  String get noChecklistTemplates =>
      'Aucun modèle de liste de contrôle disponible.';

  @override
  String get checklistSubmitted => 'Liste de contrôle envoyée.';

  @override
  String get submitChecklist => 'Envoyer la liste de contrôle';

  @override
  String get completeChecklist => 'Terminer la liste de contrôle';

  @override
  String get change => 'Modifier';

  @override
  String get startChecklist => 'Commencer la liste de contrôle';

  @override
  String get serviceReportTitle => 'Rapport d’intervention';

  @override
  String get technicianNotes => 'Notes du technicien';

  @override
  String get hoursWorked => 'Heures travaillées';

  @override
  String get technicianSignature => 'Signature du technicien';

  @override
  String get signHere => 'Signer ici';

  @override
  String get clearSignature => 'Effacer';

  @override
  String get saveSignature => 'Enregistrer la signature';

  @override
  String get signatureSaved => 'Signature enregistrée.';

  @override
  String get signatureCaptured => 'Signature recueillie';

  @override
  String get submitReport => 'Envoyer le rapport';

  @override
  String get reportSubmitted => 'Rapport envoyé.';

  @override
  String get invalidNumber => 'Saisissez un nombre valide';

  @override
  String get partsTitle => 'Registre des pièces';

  @override
  String get partName => 'Nom de la pièce';

  @override
  String get partNumber => 'Numéro de pièce';

  @override
  String get quantity => 'Quantité';

  @override
  String get unitCost => 'Coût unitaire';

  @override
  String get supplier => 'Fournisseur';

  @override
  String get addPart => 'Ajouter une pièce';

  @override
  String get noParts => 'Aucune pièce consignée.';

  @override
  String get invoicesTitle => 'Factures';

  @override
  String get invoiceNumber => 'N° de facture';

  @override
  String get amount => 'Montant';

  @override
  String get overdue => 'En retard';

  @override
  String get unpaid => 'Impayée';

  @override
  String get paid => 'Payée';

  @override
  String get draft => 'Brouillon';

  @override
  String get markPaid => 'Marquer comme payée';

  @override
  String get noInvoices => 'Aucune facture trouvée.';

  @override
  String get operatorChecklistTitle => 'Inspection quotidienne';

  @override
  String get selectAsset => 'Choisir un équipement';

  @override
  String get maintenanceFlagTitle => 'Signaler pour entretien';

  @override
  String get flagInfo =>
      'Les problèmes signalés sont envoyés directement à l’équipe d’entretien.';

  @override
  String get issueDescription => 'Décrivez le problème';

  @override
  String get flagIssue => 'Signaler le problème';

  @override
  String get flagSubmitted => 'Problème signalé.';

  @override
  String get submitFlag => 'Envoyer le signalement';

  @override
  String get priorityLow => 'Faible';

  @override
  String get priorityMedium => 'Moyenne';

  @override
  String get priorityHigh => 'Élevée';

  @override
  String get confirmDelete => 'Confirmer la suppression';

  @override
  String get confirmDeleteMessage => 'Cette action est irréversible.';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get save => 'Enregistrer';

  @override
  String get edit => 'Modifier';

  @override
  String get retry => 'Réessayer';

  @override
  String get search => 'Rechercher';

  @override
  String get back => 'Retour';

  @override
  String get done => 'Terminé';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get settings => 'Paramètres';

  @override
  String get language => 'Langue';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Español';

  @override
  String get enginesTitle => 'Moteurs';

  @override
  String get noEngines => 'Aucun moteur trouvé.';

  @override
  String get addEngine => 'Ajouter un moteur';

  @override
  String get editEngine => 'Modifier le moteur';

  @override
  String get engineLabel => 'Nom';

  @override
  String get engineKind => 'Type';

  @override
  String get currentHours => 'Heures actuelles';

  @override
  String get enginesCount => 'moteurs';

  @override
  String get hourLogsTitle => 'Journal des heures';

  @override
  String get noHourLogs => 'Aucune heure consignée.';

  @override
  String get logHours => 'Consigner les heures';

  @override
  String get clientsTitle => 'Clients';

  @override
  String get searchClients => 'Rechercher des clients…';

  @override
  String get noClients => 'Aucun client trouvé.';

  @override
  String get clientDetails => 'Détails du client';

  @override
  String get orgCodesTitle => 'Codes d’organisation';

  @override
  String get noOrgCodes => 'Aucun code d’organisation trouvé.';

  @override
  String get createOrgCode => 'Créer un code d’organisation';

  @override
  String get intendedRole => 'Rôle prévu';

  @override
  String get maxUses => 'Nombre maximal d’utilisations';

  @override
  String get singleUse => 'Usage unique';

  @override
  String get expirationDate => 'Date d’expiration (facultatif)';

  @override
  String get upcomingServices => 'Interventions à venir';

  @override
  String get noReminders => 'Aucun rappel d’entretien.';

  @override
  String get dueSoon => 'À faire bientôt';

  @override
  String get upcomingLabel => 'À venir';

  @override
  String get laterLabel => 'Plus tard';

  @override
  String get dueAt => 'À faire le';

  @override
  String get remaining => 'restant(s)';

  @override
  String get acknowledgeReminder => 'Confirmer le rappel';

  @override
  String get acknowledgeReminderMessage =>
      'Marquer ce rappel d’entretien comme confirmé ?';

  @override
  String get generateInvoice => 'Générer une facture';

  @override
  String get generateFromWorkOrder => 'Générer à partir d’un bon de travail';

  @override
  String get invoiceDetail => 'Facture';

  @override
  String get invoiceSummary => 'Sommaire de la facture';

  @override
  String get lineItems => 'Postes';

  @override
  String get labour => 'Main-d’œuvre';

  @override
  String get partsWithMarkup => 'Pièces (avec majoration)';

  @override
  String get partsTotal => 'Total des pièces';

  @override
  String get consumables => 'Consommables (5 %)';

  @override
  String get editLineItems => 'Modifier les postes';

  @override
  String get subtotal => 'Sous-total';

  @override
  String get subtotalLabel => 'Sous-total';

  @override
  String get ivaLabel => 'IVA (16 %)';

  @override
  String get totalDue => 'Total à payer';

  @override
  String get exchangeRate => 'Taux de change';

  @override
  String get refreshExchangeRate => 'Actualiser le taux de change';

  @override
  String get invoiceGenerated => 'Facture générée.';

  @override
  String get invoiceSaved => 'Facture mise à jour.';

  @override
  String get invoiceSent => 'Facture marquée comme envoyée.';

  @override
  String get sendInvoice => 'Partager la facture';

  @override
  String get invoiceMarkedPaid => 'Facture marquée comme payée.';

  @override
  String get exportPdf => 'Partager le PDF';

  @override
  String get exportExcel => 'Partager le fichier Excel';

  @override
  String get downloadPdf => 'Télécharger le PDF';

  @override
  String get downloadExcel => 'Télécharger le fichier Excel';

  @override
  String get noCompletedWorkOrders =>
      'Aucun bon de travail terminé à facturer.';

  @override
  String get selectWorkOrderForInvoice => 'Choisir un bon de travail terminé';

  @override
  String get viewInvoice => 'Voir la facture';

  @override
  String get addPhotos => 'Ajouter des photos';

  @override
  String get photos => 'Photos';

  @override
  String get gallery => 'Galerie';

  @override
  String get camera => 'Appareil photo';

  @override
  String get uploadingSignature => 'Téléversement de la signature…';

  @override
  String get photoAdded => 'Photo ajoutée.';

  @override
  String get photoUploadError => 'Échec du téléversement de la photo.';

  @override
  String get serviceReportPhotos => 'Photos du travail';

  @override
  String get serviceReportPhotosHint =>
      'Joindre des photos prises pendant les travaux';

  @override
  String get preDeparture => 'Avant le départ';

  @override
  String get preTripResults => 'Résultats de l’inspection avant départ';

  @override
  String get recentPreTripChecks => 'Inspections récentes avant départ';

  @override
  String get noRecentChecks => 'Aucune inspection avant départ enregistrée.';

  @override
  String get checkResult => 'Résultat';

  @override
  String get liveTelemetry => 'Télémétrie en direct';

  @override
  String get lastReading => 'Dernière lecture';

  @override
  String get telemetryHistory => 'Historique de la télémétrie';

  @override
  String get noTelemetry => 'Aucune donnée de télémétrie disponible.';

  @override
  String get rpm => 'tr/min';

  @override
  String get coolantTemp => 'Liquide de refroidissement (°C)';

  @override
  String get oilPressure => 'Huile (lb/po²)';

  @override
  String get batteryVoltage => 'Batterie (V)';

  @override
  String get throttle => 'Accélérateur';

  @override
  String get fuelRate => 'Débit de carburant';

  @override
  String get telemetryAlerts => 'Alertes';

  @override
  String get noAlerts => 'Aucune alerte active.';

  @override
  String get acknowledgeAlert => 'Confirmer';

  @override
  String get alertAcknowledged => 'Alerte confirmée.';

  @override
  String get flaggedIssues => 'Problèmes signalés';

  @override
  String get noFlaggedIssues => 'Aucun problème signalé.';

  @override
  String get maintenanceFlags => 'Signalements d’entretien';

  @override
  String get noMaintenanceFlags => 'Aucun signalement d’entretien.';

  @override
  String get openIssues => 'Problèmes en cours';

  @override
  String get resolvedIssues => 'Résolus';

  @override
  String get noPreTripChecks => 'Aucune inspection avant départ enregistrée.';

  @override
  String get readings => 'Lectures';

  @override
  String get alerts => 'Alertes';

  @override
  String get selectDateRange => 'Choisir une période';

  @override
  String get noTelemetryData => 'Aucune donnée pour la période sélectionnée.';

  @override
  String get battery => 'Batterie (V)';

  @override
  String get boostPressure => 'Pression de suralimentation (lb/po²)';

  @override
  String get torque => 'Couple';

  @override
  String get engineHours => 'Heures moteur';

  @override
  String get partsInventoryTitle => 'Inventaire des pièces';

  @override
  String get searchParts => 'Rechercher des pièces…';

  @override
  String get noInventory => 'Aucune pièce en inventaire.';

  @override
  String get addInventoryItem => 'Ajouter une pièce à l’inventaire';

  @override
  String get editInventoryItem => 'Modifier l’article en inventaire';

  @override
  String get qtyOnHand => 'Quantité en stock';

  @override
  String get minStockLevel => 'Niveau minimal de stock';

  @override
  String get lastUnitCost => 'Dernier coût unitaire';

  @override
  String get partLocation => 'Emplacement';

  @override
  String get pmPartsTitle => 'Pièces requises';

  @override
  String get noPmParts => 'Aucune pièce requise configurée.';

  @override
  String get addPmPart => 'Ajouter une pièce requise';

  @override
  String get editPmPart => 'Modifier la pièce requise';

  @override
  String get partsUnit => 'Unité';

  @override
  String get partsReady => 'Prêtes';

  @override
  String get partsPartial => 'Partiellement prêtes';

  @override
  String get partsNotReady => 'Non prêtes';

  @override
  String partsMissing(int count) {
    return '$count manquante(s)';
  }

  @override
  String get partsReadiness => 'État des pièces';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get noNotifications => 'Aucune notification pour le moment.';

  @override
  String get markAllRead => 'Tout marquer comme lu';

  @override
  String get serviceReportListTitle => 'Rapports d’intervention';

  @override
  String get noServiceReports => 'Aucun rapport d’intervention pour le moment.';

  @override
  String get newReport => 'Nouveau rapport';

  @override
  String get subscriptionTier => 'Forfait';

  @override
  String get upgradeRequired => 'Mise à niveau requise';

  @override
  String upgradeMessage(String tier) {
    return 'Cette fonction nécessite le forfait $tier. Communiquez avec Vórtice pour passer à un autre forfait.';
  }

  @override
  String get gotIt => 'Compris';

  @override
  String get tierFree => 'Gratuit';

  @override
  String get tierManaged => 'Géré';

  @override
  String get tierPlanning => 'Planification';

  @override
  String get tierTelemetry => 'Télémétrie';

  @override
  String get tierPredictive => 'Prédictif';

  @override
  String get issueInvoice => 'Émettre la facture';

  @override
  String get voidInvoice => 'Annuler la facture';

  @override
  String get voidInvoiceReason => 'Motif de l’annulation';

  @override
  String get invoiceIssueExplanation =>
      'L’émission fige ces détails et rend la facture visible au client. Aucun courriel ni fichier n’est envoyé.';

  @override
  String get invoiceSharingExplanation =>
      'Partagez le fichier PDF ou Excel séparément. Le partage ne confirme pas sa réception.';

  @override
  String get invoiceVoidedExplanation =>
      'Cette facture est annulée. Générez un nouveau brouillon à partir du même bon de travail pour la corriger. La facture originale reste dans l’historique.';

  @override
  String get invoiceStatusDraft => 'Brouillon';

  @override
  String get invoiceStatusIssued => 'Émise';

  @override
  String get invoiceStatusPaid => 'Payée';

  @override
  String get invoiceStatusVoided => 'Annulée';

  @override
  String get invoiceStatusUpdated => 'État de la facture mis à jour.';

  @override
  String get invoiceFileError =>
      'Impossible de créer le fichier de facture. Actualisez et réessayez.';

  @override
  String get invoiceRateError =>
      'Le taux de change en direct est indisponible. Réessayez lorsque vous serez en ligne.';

  @override
  String get invoiceRateUpdated => 'Taux de change mis à jour.';

  @override
  String get partsAdjustment => 'Ajustement des pièces';
}
