export type Delivery = { id: string; lease: string; token: string; locale: string;
  notification_id: string; user_id: string; type: string; reference_id: string };

export function notificationTitle(type: string, locale: string): string {
  const spanish = locale.toLowerCase().startsWith("es");
  switch (type) {
    case "work_order":
    case "maintenance_assignment": return spanish ? "Trabajo asignado" : "Work assigned";
    case "urgent_fault": return spanish ? "Falla urgente" : "Urgent fault";
    case "maintenance_return": return spanish ? "Informe devuelto para corregir" : "Report returned for correction";
    case "inspection_due": return spanish ? "Inspección próxima a vencer" : "Inspection due";
    default: return spanish ? "Nueva actividad en Vortice Next" : "New activity in Vortice Next";
  }
}

export function fcmMessage(row: Delivery) {
  // Titles identify the event; names and report details stay in the signed-in app.
  // The authenticated inbox checks current access when the app is opened.
  return { message: { token: row.token,
    notification: { title: notificationTitle(row.type, row.locale), body: row.locale.toLowerCase().startsWith("es")
      ? "Tienes una actualización. Abre la app para verla."
      : "You have an update. Open the app to view it." },
    data: { notification_id: row.notification_id, recipient_id: row.user_id },
    android: { priority: "HIGH", notification: { tag: row.notification_id } },
    apns: { headers: { "apns-collapse-id": row.notification_id }, payload: { aps: { sound: "default" } } },
  } };
}

export function isInvalidToken(result: unknown): boolean {
  const value = result as { error?: { details?: { errorCode?: string }[] } };
  return value?.error?.details?.some((entry) => entry.errorCode === "UNREGISTERED") ?? false;
}
