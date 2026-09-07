import 'package:flutter/material.dart';
import 'package:vortice_app/models/service_request.dart';

const kServiceRequestOtherAssetValue = '__other_asset__';

bool isOtherAssetSelection(String? assetSelection) =>
    assetSelection == kServiceRequestOtherAssetValue;

double? parseServiceRequestEngineHours(String? text) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed.replaceAll(',', ''));
}

String? validateServiceRequestAssetSelection(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please choose an asset or select Other';
  }
  return null;
}

String? validateServiceRequestOtherAssetName(
  String? value, {
  required bool isOtherAsset,
}) {
  if (isOtherAsset && (value == null || value.trim().isEmpty)) {
    return 'Please describe the asset';
  }
  return null;
}

String? validateServiceRequestEngineHours(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = parseServiceRequestEngineHours(text);
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    return 'Enter valid engine hours';
  }
  return null;
}

String? validateServiceRequestDescription(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Please describe the issue';
  }
  return null;
}

String? validateServiceRequestContact(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Please provide a phone number or WhatsApp';
  }
  return null;
}

String? resolveServiceRequestAssetId(String? assetSelection) {
  if (isOtherAssetSelection(assetSelection)) return null;
  return assetSelection;
}

String? resolveServiceRequestOtherAssetName(
  String? assetSelection,
  String otherAssetName,
) {
  if (!isOtherAssetSelection(assetSelection)) return null;
  final trimmed = otherAssetName.trim();
  return trimmed.isEmpty ? null : trimmed;
}

IconData serviceRequestKindIcon(ServiceRequestKind kind) => switch (kind) {
      ServiceRequestKind.breakdown => Icons.warning_amber_outlined,
      ServiceRequestKind.serviceMaintenance => Icons.build_outlined,
      ServiceRequestKind.safetyConcern => Icons.health_and_safety_outlined,
      ServiceRequestKind.otherIssue => Icons.more_horiz,
    };

String requestText(BuildContext context, String value) => Localizations.localeOf(context).languageCode == 'es' ? (_requestSpanish[value] ?? value) : value;
const _requestSpanish = <String, String>{
  "Request Service": "Solicitar servicio",
  "Machine": "Equipo",
  "Pick the asset this request is for.": "Selecciona el equipo de esta solicitud.",
  "Other asset": "Otro equipo",
  "Machine name, unit number, or description": "Nombre, número de unidad o descripción",
  "Request type": "Tipo de solicitud",
  "Choose the closest match.": "Selecciona la opción más adecuada.",
  "Engine hours": "Horas del motor",
  "Optional, but this will prefill the work order if you know it.": "Opcional. Si lo sabes, se incluirá en la orden de trabajo.",
  "e.g. 1250.5": "p. ej. 1250.5",
  "Details": "Detalles",
  "Add symptoms, warning signs, leaks or damage, unusual noises, when it started, and anything else that helps the technician prepare.": "Incluye síntomas, alarmas, fugas o daños, ruidos, cuándo comenzó y otros detalles útiles.",
  "Describe the issue or service needed...": "Describe el problema o servicio necesario...",
  "Contact": "Contacto",
  "Best number for a call or WhatsApp message.": "Número de contacto para llamadas o WhatsApp.",
  "Phone number or WhatsApp": "Teléfono o WhatsApp",
  "Photos": "Fotos",
  "Optional, but helpful for leaks, damage, alarms, or access.": "Opcionales. Ayudan a mostrar fugas, daños, alarmas o acceso.",
  "Select asset": "Seleccionar equipo",
  "Other": "Otro",
  "Send Request": "Enviar solicitud",
  "Gallery": "Galería",
  "Camera": "Cámara",
  "Breakdown": "Avería",
  "Service / maintenance": "Servicio / Mantenimiento",
  "Safety concern": "Riesgo de seguridad",
  "Other issue": "Otro problema",
  "Please choose an asset or select Other": "Selecciona un equipo u Otro",
  "Please describe the asset": "Describe el equipo",
  "Enter valid engine hours": "Introduce horas válidas",
  "Please describe the issue": "Describe el problema",
  "Please provide a phone number or WhatsApp": "Introduce un teléfono o WhatsApp",
  "Send Vórtice the key details so we can prepare faster and build the work order from clean information.": "Envía los detalles a Vórtice para preparar el servicio y la orden de trabajo."
};
