// Shared WhatsApp Cloud API helpers for the subscription edge functions.
//
// Credentials resolve in this order:
//   1. Edge function secrets  WHATSAPP_ACCESS_TOKEN / WHATSAPP_PHONE_NUMBER_ID
//   2. app_config row  key='whatsapp_credentials'  (editable from admin panel)
// Message TEXT always comes from the whatsapp_templates table so the manager
// can rewrite every message without touching code.

export interface WhatsAppConfig {
  accessToken: string;
  phoneNumberId: string;
}

export async function loadWhatsAppConfig(
  sb: any,
): Promise<WhatsAppConfig | null> {
  let accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
  let phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID") ?? "";
  if (!accessToken || !phoneNumberId) {
    try {
      const { data } = await sb.from("app_config")
        .select("value").eq("key", "whatsapp_credentials").maybeSingle();
      const v = (data?.value ?? {}) as Record<string, string>;
      accessToken = accessToken || v.access_token || "";
      phoneNumberId = phoneNumberId || v.phone_number_id || "";
    } catch (_) { /* unconfigured */ }
  }
  // Placeholder values from the seed migration are not real credentials.
  if (!accessToken || !phoneNumberId ||
    accessToken.startsWith("YOUR_") || phoneNumberId.startsWith("YOUR_")) {
    return null;
  }
  return { accessToken, phoneNumberId };
}

/** Loads an active template's text by key; returns null when missing/disabled. */
export async function loadTemplate(sb: any, key: string): Promise<string | null> {
  try {
    const { data } = await sb.from("whatsapp_templates")
      .select("message_text,active").eq("template_key", key).maybeSingle();
    if (!data || data.active === false) return null;
    return String(data.message_text ?? "");
  } catch (_) {
    return null;
  }
}

/** Replaces {{placeholders}} — unknown ones are removed rather than leaked. */
export function renderTemplate(
  text: string,
  vars: Record<string, string>,
): string {
  return text.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, k) => vars[k] ?? "");
}

/** Normalizes an Indian mobile to WhatsApp's international digits (91xxxxxxxxxx). */
export function toWaNumber(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.length === 10) return "91" + digits;
  return digits; // already has country code
}

/** Last 10 digits — used to match an incoming WhatsApp sender to a member. */
export function last10(phone: string): string {
  return phone.replace(/\D/g, "").slice(-10);
}

export async function sendWhatsAppText(
  cfg: WhatsAppConfig,
  to: string,
  text: string,
): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch(
      `https://graph.facebook.com/v19.0/${cfg.phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${cfg.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to,
          type: "text",
          text: { body: text },
        }),
      },
    );
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      return { ok: false, error: err?.error?.message ?? `HTTP ${res.status}` };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "send failed" };
  }
}

/** Sends an approved Meta message template — required to message someone who
 * hasn't replied to the business within the last 24 hours (sendWhatsAppText
 * would be silently rejected in that case). bodyParams fill {{1}}, {{2}}, ...
 * in order, matching whatever positional params the template was approved with. */
export async function sendWhatsAppTemplate(
  cfg: WhatsAppConfig,
  to: string,
  templateName: string,
  languageCode: string,
  bodyParams: string[],
): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch(
      `https://graph.facebook.com/v19.0/${cfg.phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${cfg.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to,
          type: "template",
          template: {
            name: templateName,
            language: { code: languageCode },
            components: [{
              type: "body",
              parameters: bodyParams.map((text) => ({ type: "text", text })),
            }],
          },
        }),
      },
    );
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      return { ok: false, error: err?.error?.message ?? `HTTP ${res.status}` };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "send failed" };
  }
}

/** Sends an approved template whose first button is a FLOW button — same as
 * sendWhatsAppTemplate but also passes the per-recipient flowToken so the
 * Flow's data endpoint can correlate the session back to a subscription. */
export async function sendWhatsAppFlowTemplate(
  cfg: WhatsAppConfig,
  to: string,
  templateName: string,
  languageCode: string,
  bodyParams: string[],
  flowToken: string,
): Promise<{ ok: boolean; error?: string }> {
  try {
    const res = await fetch(
      `https://graph.facebook.com/v19.0/${cfg.phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${cfg.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to,
          type: "template",
          template: {
            name: templateName,
            language: { code: languageCode },
            components: [
              {
                type: "body",
                parameters: bodyParams.map((text) => ({ type: "text", text })),
              },
              {
                type: "button",
                sub_type: "flow",
                index: "0",
                parameters: [
                  { type: "action", action: { flow_token: flowToken } },
                ],
              },
            ],
          },
        }),
      },
    );
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      return { ok: false, error: err?.error?.message ?? `HTTP ${res.status}` };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : "send failed" };
  }
}

/** yyyy-mm-dd for "today + offsetDays" in IST (the kitchen's timezone). */
export function istDate(offsetDays = 0): string {
  const ist = new Date(Date.now() + (5.5 * 60 + offsetDays * 24 * 60) * 60_000);
  return ist.toISOString().slice(0, 10);
}

/** Human-friendly date for messages, e.g. "Tue, 15 Jul". */
export function prettyDate(yyyyMmDd: string): string {
  const d = new Date(yyyyMmDd + "T00:00:00");
  return d.toLocaleDateString("en-IN", {
    weekday: "short", day: "numeric", month: "short",
  });
}

/** 24h hour/minute -> "11:00 PM", for admin-configured times shown in messages. */
export function formatTime12h(hour: number, minute: number): string {
  const period = hour >= 12 ? "PM" : "AM";
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${h12}:${minute.toString().padStart(2, "0")} ${period}`;
}
