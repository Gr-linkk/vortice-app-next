// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get loginSubtitle => 'Mantenimiento Marino y Equipos Pesados';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get forgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get noAccount => '¿No tienes cuenta?';

  @override
  String get register => 'Registrarse';

  @override
  String get fieldRequired => 'Este campo es obligatorio';

  @override
  String get invalidEmail => 'Ingresa un correo electrónico válido';

  @override
  String get passwordTooShort =>
      'La contraseña debe tener al menos 6 caracteres';

  @override
  String get registerTitle => 'Crear cuenta';

  @override
  String get registerSubtitle =>
      'Ingresa el código de tu organización para comenzar.';

  @override
  String get iHaveOrgCode => 'Tengo un código de organización';

  @override
  String get newClientSignup => 'Registro como nuevo cliente';

  @override
  String get orgCode => 'Código de organización';

  @override
  String get orgCodeHelper => 'Solicita este código a tu gerente de cuenta';

  @override
  String get fullName => 'Nombre completo';

  @override
  String get phone => 'Teléfono';

  @override
  String get vesselName => 'Nombre de la embarcación';

  @override
  String get vesselType => 'Tipo de embarcación';

  @override
  String get marinaLocation => 'Marina / Ubicación';

  @override
  String get vesselTypeSailboat => 'Velero';

  @override
  String get vesselTypePowerboat => 'Lancha';

  @override
  String get vesselTypeYacht => 'Yate';

  @override
  String get vesselTypeOther => 'Otro';

  @override
  String get confirmPassword => 'Confirmar contraseña';

  @override
  String get passwordsDoNotMatch => 'Las contraseñas no coinciden';

  @override
  String get invalidOrgCode =>
      'Código de organización inválido. Verifica e intenta de nuevo.';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get alreadyHaveAccount => '¿Ya tienes cuenta?';

  @override
  String greeting(String name) {
    return 'Hola, $name';
  }

  @override
  String get ownerDashboardTitle => 'Panel principal';

  @override
  String get employeeDashboardTitle => 'Mis órdenes';

  @override
  String get clientDashboardTitle => 'Mi equipo';

  @override
  String get operatorDashboardTitle => 'Operaciones del día';

  @override
  String get clientDashboardSubtitle =>
      'Supervisa tu flota e historial de servicios.';

  @override
  String get operatorDashboardSubtitle =>
      'Inicia tu checklist diario o reporta un problema.';

  @override
  String get navDashboard => 'Inicio';

  @override
  String get navAssets => 'Activos';

  @override
  String get navWorkOrders => 'Órdenes';

  @override
  String get navServiceReports => 'Reportes';

  @override
  String get navParts => 'Refacciones';

  @override
  String get navInvoices => 'Facturas';

  @override
  String get navChecklist => 'Checklist';

  @override
  String get navFlags => 'Alertas';

  @override
  String get totalAssets => 'Total de activos';

  @override
  String get openWorkOrders => 'Órdenes abiertas';

  @override
  String get recentWorkOrders => 'Órdenes recientes';

  @override
  String get viewAll => 'Ver todo';

  @override
  String get noWorkOrders => 'No hay órdenes de trabajo.';

  @override
  String get assignedToMe => 'Asignadas a mí';

  @override
  String get noAssignedWorkOrders => 'No tienes órdenes de trabajo activas.';

  @override
  String get myFleet => 'Mi flota';

  @override
  String get noAssets => 'No se encontraron activos.';

  @override
  String get availableAssets => 'Activos disponibles';

  @override
  String get activeServices => 'Servicios activos';

  @override
  String get assetsTitle => 'Activos';

  @override
  String get assetType => 'Tipo de activo';

  @override
  String get searchAssets => 'Buscar activos...';

  @override
  String get addAsset => 'Agregar activo';

  @override
  String get saveAsset => 'Guardar activo';

  @override
  String get assetDetail => 'Detalle del activo';

  @override
  String get assetDetails => 'Detalles';

  @override
  String get assetName => 'Nombre del activo';

  @override
  String get serialNumber => 'Número de serie';

  @override
  String get model => 'Modelo';

  @override
  String get manufacturer => 'Fabricante';

  @override
  String get year => 'Año';

  @override
  String get location => 'Ubicación';

  @override
  String get status => 'Estado';

  @override
  String get notes => 'Notas';

  @override
  String get assetNotFound => 'Activo no encontrado.';

  @override
  String get invalidYear => 'Ingresa un año válido';

  @override
  String get editAsset => 'Editar Activo';

  @override
  String get addEngineHint =>
      'Agrega el motor principal (puedes agregar más después)';

  @override
  String get reassignTech => 'Reasignar Técnico';

  @override
  String get srComplaint => '1 — Queja';

  @override
  String get srComplaintSub =>
      'Problema reportado por el cliente en sus palabras';

  @override
  String get srCause => '2 — Causa';

  @override
  String get srCauseSub => 'Causa raíz diagnosticada del problema';

  @override
  String get srCorrection => '3 — Corrección';

  @override
  String get srCorrectionSub => 'Trabajo realizado y piezas reemplazadas';

  @override
  String get srSecondaryDamage => '4 — Daño Secundario';

  @override
  String get srSecondaryDamageSub =>
      'Hallazgos adicionales descubiertos durante este trabajo';

  @override
  String get srComments => '5 — Comentarios';

  @override
  String get srCommentsSub =>
      'Recomendaciones, próximo servicio, aspectos a vigilar';

  @override
  String get srComplaintHint => '¿Qué reportó el cliente?';

  @override
  String get srCauseHint => '¿Qué causó el problema?';

  @override
  String get srCorrectionHint => '¿Qué trabajo se realizó? ¿Qué se reemplazó?';

  @override
  String get srSecondaryDamageHint =>
      'Daños o problemas encontrados fuera del alcance principal del trabajo';

  @override
  String get srCommentsHint => 'Algo que el cliente deba saber o vigilar';

  @override
  String get workOrdersTitle => 'Órdenes de trabajo';

  @override
  String get workOrderDetail => 'Orden de trabajo';

  @override
  String get workOrderTitle => 'Título';

  @override
  String get createWorkOrder => 'Crear orden';

  @override
  String get linkedAsset => 'Activo vinculado';

  @override
  String get noAsset => 'Sin activo';

  @override
  String get description => 'Descripción';

  @override
  String get jobType => 'Tipo de trabajo';

  @override
  String get scheduledDate => 'Fecha programada';

  @override
  String get priority => 'Prioridad';

  @override
  String get dueDate => 'Fecha límite';

  @override
  String get completedAt => 'Completado';

  @override
  String get selectDate => 'Seleccionar fecha';

  @override
  String get startWorkOrder => 'Iniciar orden';

  @override
  String get reopenWorkOrder => 'Reabrir orden';

  @override
  String get completeWorkOrder => 'Marcar completado';

  @override
  String get statusOpen => 'Abierta';

  @override
  String get statusInProgress => 'En progreso';

  @override
  String get statusCompleted => 'Completada';

  @override
  String get actions => 'Acciones';

  @override
  String get viewChecklist => 'Ver checklist';

  @override
  String get serviceReport => 'Reporte de servicio';

  @override
  String get selectWorkOrder => 'Por favor selecciona una orden de trabajo';

  @override
  String get linkedWorkOrder => 'Orden vinculada';

  @override
  String get notFound => 'No encontrado.';

  @override
  String get woDetailsSection => 'Detalles';

  @override
  String get assignedTech => 'Técnico asignado';

  @override
  String get hoursAtStart => 'Horas motor (inicio)';

  @override
  String get hoursAtEnd => 'Horas motor (fin)';

  @override
  String get labourHours => 'Horas de trabajo';

  @override
  String get billableRate => 'Tarifa facturable';

  @override
  String get wageRate => 'Tarifa salarial';

  @override
  String get internalNotes => 'Notas internas';

  @override
  String get onHoldReason => 'Razón de pausa';

  @override
  String get editWorkOrder => 'Editar orden de trabajo';

  @override
  String get checklistTitle => 'Checklist';

  @override
  String get selectTemplate => 'Seleccionar plantilla';

  @override
  String get noChecklistTemplates =>
      'No hay plantillas de checklist disponibles.';

  @override
  String get checklistSubmitted => 'Checklist enviado correctamente.';

  @override
  String get submitChecklist => 'Enviar checklist';

  @override
  String get completeChecklist => 'Completar checklist';

  @override
  String get change => 'Cambiar';

  @override
  String get startChecklist => 'Iniciar checklist';

  @override
  String get serviceReportTitle => 'Reporte de servicio';

  @override
  String get technicianNotes => 'Notas del técnico';

  @override
  String get hoursWorked => 'Horas trabajadas';

  @override
  String get technicianSignature => 'Firma del técnico';

  @override
  String get signHere => 'Firmar aquí';

  @override
  String get clearSignature => 'Limpiar';

  @override
  String get saveSignature => 'Guardar firma';

  @override
  String get signatureSaved => 'Firma guardada.';

  @override
  String get signatureCaptured => 'Firma capturada';

  @override
  String get submitReport => 'Enviar reporte';

  @override
  String get reportSubmitted => 'Reporte enviado correctamente.';

  @override
  String get invalidNumber => 'Ingresa un número válido';

  @override
  String get partsTitle => 'Bitácora de refacciones';

  @override
  String get partName => 'Nombre de la pieza';

  @override
  String get partNumber => 'Número de parte';

  @override
  String get quantity => 'Cant.';

  @override
  String get unitCost => 'Costo unitario';

  @override
  String get supplier => 'Proveedor';

  @override
  String get addPart => 'Agregar pieza';

  @override
  String get noParts => 'No hay refacciones registradas.';

  @override
  String get invoicesTitle => 'Facturas';

  @override
  String get invoiceNumber => 'Factura #';

  @override
  String get amount => 'Monto';

  @override
  String get overdue => 'Vencidas';

  @override
  String get unpaid => 'Pendientes';

  @override
  String get paid => 'Pagadas';

  @override
  String get draft => 'Borrador';

  @override
  String get markPaid => 'Marcar pagada';

  @override
  String get noInvoices => 'No hay facturas.';

  @override
  String get operatorChecklistTitle => 'Checklist diario';

  @override
  String get selectAsset => 'Seleccionar activo';

  @override
  String get maintenanceFlagTitle => 'Reportar para mantenimiento';

  @override
  String get flagInfo =>
      'Los problemas reportados se envían directamente al equipo de mantenimiento.';

  @override
  String get issueDescription => 'Describe el problema';

  @override
  String get flagIssue => 'Reportar problema';

  @override
  String get flagSubmitted => 'Problema reportado correctamente.';

  @override
  String get submitFlag => 'Enviar reporte';

  @override
  String get priorityLow => 'Baja';

  @override
  String get priorityMedium => 'Media';

  @override
  String get priorityHigh => 'Alta';

  @override
  String get confirmDelete => 'Confirmar eliminación';

  @override
  String get confirmDeleteMessage => 'Esta acción no se puede deshacer.';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get save => 'Guardar';

  @override
  String get edit => 'Editar';

  @override
  String get retry => 'Reintentar';

  @override
  String get search => 'Buscar';

  @override
  String get back => 'Atrás';

  @override
  String get done => 'Listo';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get settings => 'Configuración';

  @override
  String get language => 'Idioma';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Español';

  @override
  String get enginesTitle => 'Motores';

  @override
  String get noEngines => 'No se encontraron motores.';

  @override
  String get addEngine => 'Agregar motor';

  @override
  String get editEngine => 'Editar motor';

  @override
  String get engineLabel => 'Etiqueta';

  @override
  String get engineKind => 'Tipo';

  @override
  String get currentHours => 'Horas actuales';

  @override
  String get enginesCount => 'motores';

  @override
  String get hourLogsTitle => 'Registro de horas';

  @override
  String get noHourLogs => 'No hay registros de horas.';

  @override
  String get logHours => 'Registrar horas';

  @override
  String get clientsTitle => 'Clientes';

  @override
  String get searchClients => 'Buscar clientes...';

  @override
  String get noClients => 'No se encontraron clientes.';

  @override
  String get clientDetails => 'Detalles del cliente';

  @override
  String get orgCodesTitle => 'Códigos de organización';

  @override
  String get noOrgCodes => 'No se encontraron códigos.';

  @override
  String get createOrgCode => 'Crear código';

  @override
  String get intendedRole => 'Rol asignado';

  @override
  String get maxUses => 'Usos máximos';

  @override
  String get singleUse => 'Un solo uso';

  @override
  String get expirationDate => 'Fecha de expiración (opcional)';

  @override
  String get upcomingServices => 'Servicios próximos';

  @override
  String get noReminders => 'No hay recordatorios de servicio.';

  @override
  String get dueSoon => 'Próximo';

  @override
  String get upcomingLabel => 'Próximamente';

  @override
  String get laterLabel => 'Más tarde';

  @override
  String get dueAt => 'Vence en';

  @override
  String get remaining => 'restantes';

  @override
  String get acknowledgeReminder => 'Confirmar recordatorio';

  @override
  String get acknowledgeReminderMessage =>
      '¿Marcar este recordatorio de servicio como confirmado?';

  @override
  String get generateInvoice => 'Generar factura';

  @override
  String get generateFromWorkOrder => 'Generar desde orden de trabajo';

  @override
  String get invoiceDetail => 'Factura';

  @override
  String get invoiceSummary => 'Resumen de factura';

  @override
  String get lineItems => 'Conceptos';

  @override
  String get labour => 'Mano de obra';

  @override
  String get partsWithMarkup => 'Refacciones (con margen)';

  @override
  String get partsTotal => 'Total refacciones';

  @override
  String get consumables => 'Consumibles (5%)';

  @override
  String get editLineItems => 'Editar conceptos';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get subtotalLabel => 'Subtotal';

  @override
  String get ivaLabel => 'IVA (16%)';

  @override
  String get totalDue => 'Total a pagar';

  @override
  String get exchangeRate => 'Tipo de cambio';

  @override
  String get refreshExchangeRate => 'Actualizar tipo de cambio';

  @override
  String get invoiceGenerated => 'Factura generada correctamente';

  @override
  String get invoiceSaved => 'Factura actualizada.';

  @override
  String get invoiceSent => 'Factura marcada como enviada.';

  @override
  String get sendInvoice => 'Compartir factura';

  @override
  String get invoiceMarkedPaid => 'Factura marcada como pagada.';

  @override
  String get exportPdf => 'Compartir PDF';

  @override
  String get exportExcel => 'Compartir Excel';

  @override
  String get downloadPdf => 'Descargar PDF';

  @override
  String get downloadExcel => 'Descargar Excel';

  @override
  String get noCompletedWorkOrders =>
      'No hay órdenes completadas para facturar.';

  @override
  String get selectWorkOrderForInvoice =>
      'Selecciona una orden de trabajo completada';

  @override
  String get viewInvoice => 'Ver factura';

  @override
  String get addPhotos => 'Agregar fotos';

  @override
  String get photos => 'Fotos';

  @override
  String get gallery => 'Galería';

  @override
  String get camera => 'Cámara';

  @override
  String get uploadingSignature => 'Subiendo firma…';

  @override
  String get photoAdded => 'Foto agregada.';

  @override
  String get photoUploadError => 'Error al subir la foto.';

  @override
  String get serviceReportPhotos => 'Fotos del trabajo';

  @override
  String get serviceReportPhotosHint =>
      'Adjunta fotos tomadas durante el trabajo';

  @override
  String get preDeparture => 'Pre-salida';

  @override
  String get preTripResults => 'Checklists de pre-salida';

  @override
  String get recentPreTripChecks => 'Checklists recientes';

  @override
  String get noRecentChecks => 'No hay checklists registrados.';

  @override
  String get checkResult => 'Resultado';

  @override
  String get liveTelemetry => 'Telemetría en vivo';

  @override
  String get lastReading => 'Última lectura';

  @override
  String get telemetryHistory => 'Historial de telemetría';

  @override
  String get noTelemetry => 'No hay datos de telemetría disponibles.';

  @override
  String get rpm => 'RPM';

  @override
  String get coolantTemp => 'Refrigerante (°C)';

  @override
  String get oilPressure => 'Aceite (PSI)';

  @override
  String get batteryVoltage => 'Batería (V)';

  @override
  String get throttle => 'Acelerador';

  @override
  String get fuelRate => 'Consumo de combustible';

  @override
  String get telemetryAlerts => 'Alertas';

  @override
  String get noAlerts => 'Sin alertas activas.';

  @override
  String get acknowledgeAlert => 'Reconocer';

  @override
  String get alertAcknowledged => 'Alerta reconocida.';

  @override
  String get flaggedIssues => 'Problemas reportados';

  @override
  String get noFlaggedIssues => 'No hay problemas reportados.';

  @override
  String get maintenanceFlags => 'Alertas de mantenimiento';

  @override
  String get noMaintenanceFlags =>
      'No hay alertas de mantenimiento reportadas.';

  @override
  String get openIssues => 'Problemas abiertos';

  @override
  String get resolvedIssues => 'Resueltos';

  @override
  String get noPreTripChecks => 'No hay checklists de pre-salida registrados.';

  @override
  String get readings => 'Lecturas';

  @override
  String get alerts => 'Alertas';

  @override
  String get selectDateRange => 'Seleccionar rango de fechas';

  @override
  String get noTelemetryData => 'Sin datos para el rango seleccionado.';

  @override
  String get battery => 'Batería (V)';

  @override
  String get boostPressure => 'Turbo (PSI)';

  @override
  String get torque => 'Torque';

  @override
  String get engineHours => 'Horas de motor';

  @override
  String get partsInventoryTitle => 'Inventario de Piezas';

  @override
  String get searchParts => 'Buscar piezas...';

  @override
  String get noInventory => 'No hay piezas en inventario.';

  @override
  String get addInventoryItem => 'Agregar Pieza al Inventario';

  @override
  String get editInventoryItem => 'Editar Pieza de Inventario';

  @override
  String get qtyOnHand => 'Cantidad Disponible';

  @override
  String get minStockLevel => 'Stock Mínimo';

  @override
  String get lastUnitCost => 'Último Costo Unitario';

  @override
  String get partLocation => 'Ubicación';

  @override
  String get pmPartsTitle => 'Piezas Requeridas';

  @override
  String get noPmParts => 'No hay requerimientos de piezas configurados.';

  @override
  String get addPmPart => 'Agregar Pieza Requerida';

  @override
  String get editPmPart => 'Editar Pieza Requerida';

  @override
  String get partsUnit => 'Unidad';

  @override
  String get partsReady => 'Listo';

  @override
  String get partsPartial => 'Parcial';

  @override
  String get partsNotReady => 'Sin Stock';

  @override
  String partsMissing(int count) {
    return '$count faltantes';
  }

  @override
  String get partsReadiness => 'Disponibilidad de Piezas';

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get noNotifications => 'Sin notificaciones por ahora.';

  @override
  String get markAllRead => 'Marcar todo como leído';

  @override
  String get serviceReportListTitle => 'Informes de Servicio';

  @override
  String get noServiceReports => 'Sin informes de servicio.';

  @override
  String get newReport => 'Nuevo Informe';

  @override
  String get subscriptionTier => 'Nivel de Suscripción';

  @override
  String get upgradeRequired => 'Actualización Requerida';

  @override
  String upgradeMessage(String tier) {
    return 'Esta función requiere un plan $tier. Contacte a Vórtice para actualizar.';
  }

  @override
  String get gotIt => 'Entendido';

  @override
  String get tierFree => 'Gratis';

  @override
  String get tierManaged => 'Gestionado';

  @override
  String get tierPlanning => 'Planificación';

  @override
  String get tierTelemetry => 'Telemetría';

  @override
  String get tierPredictive => 'Predictivo';
}
