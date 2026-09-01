import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendPush } from "../_shared/push.ts";

// Fires when a meal is confirmed (via the user web app's confirm_meal RPC
// or any other path that inserts/updates meal_confirmations with
// status = 'confirmed'). Called by a Postgres trigger via pg_net.
//
// Pushes to all admin/sub_manager device_tokens so the kitchen knows
// a member has confirmed today's meal.

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
    const subscriptionId = body?.subscription_id ?? "";
    const mealDate = body?.meal_date ?? "";

    // Look up the member's name for the notification text.
    let memberName = "A member";
    if (subscriptionId) {
      const { data: sub } = await sb.from("subscriptions")
        .select("customer_name")
        .eq("id", subscriptionId)
        .maybeSingle();
      if (sub?.customer_name) memberName = sub.customer_name;
    }

    // Push to admin/sub_manager staff only.
    const { data: managers } = await sb.from("profiles").select("id")
      .in("role", ["admin", "developer", "sub_manager"]);
    const managerIds = (managers ?? []).map((p: any) => p.id);
    if (managerIds.length === 0) return json({ sent: 0, failed: 0 });

    const { data: tokens, error: tErr } = await sb
      .from("device_tokens")
      .select("id, fcm_token")
      .in("user_id", managerIds);
    if (tErr) return json({ error: "Token lookup failed: " + tErr.message }, 500);
    if (!tokens || tokens.length === 0) return json({ sent: 0, failed: 0 });

    const dateLabel = mealDate || "today";
    const { sent, failed } = await sendPush(
      sb, serviceAccountJson, tokens,
      "Meal confirmed",
      `${memberName} confirmed their meal for ${dateLabel}.`,
      "/subs",
    );

    return json({ sent, failed });
  } catch (e) {
    console.error("send-meal-confirmation-push error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
