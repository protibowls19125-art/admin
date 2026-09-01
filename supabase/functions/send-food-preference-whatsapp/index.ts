import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  loadTemplate,
  loadWhatsAppConfig,
  sendWhatsAppTemplate,
  toWaNumber,
} from "../_shared/whatsapp.ts";

// On-demand: asks every active member (or a picked subset) whether they want
// veg, non-veg, or mixed meals — template `food_preference_confirm`, editable
// in the admin panel. No schedule/gating, unlike send-daily-meal-whatsapp —
// this is fired manually from the admin panel's "Send now" for this template.
//
// Callable by:
//   • pg_cron          → header  x-cron-secret: <CRON_SECRET env>
//   • the admin panel  → Authorization: Bearer <manager JWT>

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
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    // ── AuthZ: cron secret OR a manager/admin JWT ────────────────────────────
    const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
    const givenSecret = req.headers.get("x-cron-secret") ?? "";
    let authorized = cronSecret.length > 0 && givenSecret === cronSecret;
    if (!authorized) {
      const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
      if (jwt) {
        const { data: userData } = await sb.auth.getUser(jwt);
        if (userData?.user) {
          const { data: profile } = await sb.from("profiles")
            .select("role").eq("id", userData.user.id).maybeSingle();
          authorized = ["admin", "developer", "sub_manager"].includes(profile?.role ?? "");
        }
      }
    }
    if (!authorized) return json({ error: "Not authorized" }, 401);

    // Manual trigger can target specific members instead of everyone active.
    let subscriptionIds: string[] | null = null;
    try {
      const body = await req.json();
      if (Array.isArray(body?.subscription_ids) && body.subscription_ids.length > 0) {
        subscriptionIds = body.subscription_ids as string[];
      }
    } catch (_) { /* no/invalid body — send to everyone active */ }

    let subsQuery = sb.from("subscriptions")
      .select("id,customer_name,phone")
      .eq("status", "active");
    if (subscriptionIds) subsQuery = subsQuery.in("id", subscriptionIds);
    const { data: subs, error: subErr } = await subsQuery;
    if (subErr) return json({ error: "Could not load members" }, 500);

    let sent = 0, failed = 0, skippedNoPhone = 0;
    let lastError: string | undefined;
    const cfg = await loadWhatsAppConfig(sb);
    // Same reasoning as daily_meal_confirm: sent as an approved Meta message
    // TEMPLATE, not free text, since the member may not have messaged us in
    // the last 24 hours.
    const tplEnabled = cfg
      ? (await loadTemplate(sb, "food_preference_confirm")) !== null
      : false;

    if (cfg && tplEnabled) {
      for (const sub of subs ?? []) {
        if (!sub.phone) {
          skippedNoPhone++;
          continue;
        }
        const r = await sendWhatsAppTemplate(
          cfg,
          toWaNumber(sub.phone),
          "food_preference_confirm",
          "en",
          [sub.customer_name || "there"],
        );
        if (r.ok) {
          sent++;
        } else {
          failed++;
          lastError = r.error;
          console.error(`WhatsApp send failed for ${sub.id} (${sub.phone}):`, r.error);
        }
      }
    }

    return json({
      ok: true,
      members: (subs ?? []).length,
      sent,
      failed,
      skippedNoPhone,
      configured: !!cfg,
      lastError,
    });
  } catch (e) {
    console.error("send-food-preference-whatsapp error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
