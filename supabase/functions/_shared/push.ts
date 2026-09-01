import { getFcmAccessToken } from "./firebase.ts";

// Shared FCM send loop — used by send-order-push-notification (new order →
// every registered device) and whatsapp-webhook (member confirms via
// WhatsApp → subs managers only). Deletes any token FCM reports as
// dead/unregistered so a stale browser doesn't fail every send forever.
export async function sendPush(
  sb: any,
  serviceAccountJson: string,
  tokens: { id: string; fcm_token: string }[],
  title: string,
  body: string,
  link = "/",
): Promise<{ sent: number; failed: number }> {
  if (tokens.length === 0) return { sent: 0, failed: 0 };
  const { token: accessToken, projectId } = await getFcmAccessToken(serviceAccountJson);

  let sent = 0, failed = 0;
  const staleIds: string[] = [];
  for (const t of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: t.fcm_token,
            notification: { title, body },
            webpush: { fcm_options: { link } },
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
      continue;
    }
    failed++;
    const errData = await res.json().catch(() => ({}));
    const errStatus = errData?.error?.status;
    if (errStatus === "NOT_FOUND" || errStatus === "UNREGISTERED") {
      staleIds.push(t.id);
    }
  }
  if (staleIds.length > 0) {
    await sb.from("device_tokens").delete().in("id", staleIds);
  }
  return { sent, failed };
}
