export type Delivery = { id: string; lease: string; token: string; locale: string;
  notification_id: string; user_id: string; type: string; reference_id: string };

export function fcmMessage(row: Delivery) {
  // Device notifications contain no asset, fault, customer or report content.
  // The authenticated inbox checks current access when the app is opened.
  return { message: { token: row.token,
    notification: { title: "Vortice Next", body: row.locale === "es"
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
