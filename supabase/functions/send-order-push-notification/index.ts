import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPush } from "../_shared/push.ts";

// Fires the moment a new order is inserted — called directly by a Postgres
// trigger (public.notify_new_order(), AFTER INSERT ON orders via pg_net; see
// MIGRATION_ORDER_PUSH_NOTIFICATIONS.sql), not polled, so the push lands
// within a second or two of the order landing — and fires even if every
// admin's browser tab is closed (real FCM push, not the old in-tab-only
// browser Notification).
//
// Pushes to EVERY registered device_tokens row — that table is only ever
// written by the admin app (push_notification_service.dart) on login, so
// every row already belongs to staff. No role filter needed.
//
// Callable only by pg_cron/pg_net → header x-cron-secret: <CRON_SECRET env>.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: { ...cors, "Content-Type": "application/json", "X-Content-Type-Options": "nosniff" },
  });

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
    const givenSecret = req.headers.get("x-cron-secret") ?? "";
    if (!(cronSecret.length > 0 && givenSecret === cronSecret)) {
      return json({ error: "Not authorized" }, 401);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    if (!serviceAccountJson) return json({ error: "Firebase not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const body = await req.json().catch(() => ({}));
    const orderNumber = body?.order_number ?? body?.order_id ?? "";

    const { data: tokens, error: tErr } = await sb
      .from("device_tokens")
      .select("id, fcm_token");
    if (tErr) return json({ error: "Token lookup failed: " + tErr.message }, 500);
    if (!tokens || tokens.length === 0) return json({ sent: 0, failed: 0 });

    const notifBody = orderNumber
      ? `Order #${String(orderNumber).toUpperCase()} just came in.`
      : "A new order just came in.";
    const { sent, failed } = await sendPush(
      sb, serviceAccountJson, tokens, "New order received", notifBody, "/orders",
    );

    return json({ sent, failed });
  } catch (e) {
    console.error("send-order-push-notification error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
