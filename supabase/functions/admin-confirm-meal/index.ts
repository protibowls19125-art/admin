import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// Pinned (not floating @2) — see admin-manage-member/index.ts for why.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.112.1";
import {
  loadTemplate,
  loadWhatsAppConfig,
  prettyDate,
  renderTemplate,
  sendWhatsAppText,
  toWaNumber,
} from "../_shared/whatsapp.ts";
import { mealsRemainingDelta } from "../_shared/meals-balance.ts";

// Manager-only manual confirm/skip for a meal_confirmations row — e.g. a
// member's free-text WhatsApp reply didn't parse as yes/no, and staff want
// to act on it directly instead of waiting for a re-reply. Sends the exact
// same confirm_ack/skip_ack WhatsApp message a real yes/no reply would have
// triggered (whatsapp-webhook), so the member sees the same confirmation
// either way — a raw DB status change alone never sends anything.
//
// POST { meal_confirmation_id, decision: 'yes' | 'no' }
// Requires a staff JWT whose profile role is admin/developer/sub_manager.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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

    const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Not authorized" }, 401);
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "Not authorized" }, 401);
    const { data: profile } = await sb.from("profiles")
      .select("role").eq("id", userData.user.id).maybeSingle();
    if (!profile ||
        !["admin", "developer", "sub_manager"].includes(profile.role ?? ""))
      return json({ error: "Forbidden" }, 403);

    // Manual override window: 11:00 AM–6:00 PM IST only — outside it,
    // managers must let the WhatsApp yes/no reply (or the cutoff
    // auto-resolve in send-daily-meal-whatsapp) settle the row instead of
    // hand-editing it. Enforced here, not just in the admin UI, since the
    // UI check alone can't stop a direct API call.
    const nowIst = new Date(Date.now() + 5.5 * 60 * 60_000);
    const istHour = nowIst.getUTCHours();
    if (istHour < 11 || istHour >= 18) {
      return json({ error: "Manual confirmation is only available 11:00 AM–6:00 PM." }, 403);
    }

    const body = await req.json();
    const mealConfirmationId = String(body.meal_confirmation_id ?? "");
    const decision = String(body.decision ?? "");
    if (!mealConfirmationId || !["yes", "no"].includes(decision)) {
      return json({ error: "Missing/invalid fields" }, 400);
    }
    const isYes = decision === "yes";

    const { data: meal } = await sb.from("meal_confirmations")
      .select("id, meal_date, status, subscription_id, "
        + "subscriptions(customer_name,phone,food_preference,subscription_plans(meals_per_day))")
      .eq("id", mealConfirmationId).maybeSingle();
    if (!meal) return json({ error: "Meal confirmation not found" }, 404);
    const sub = (meal as any).subscriptions;
    if (!sub) return json({ error: "Member not found" }, 404);

    const now = new Date().toISOString();
    const { error: upErr } = await sb.from("meal_confirmations").update({
      status: isYes ? "confirmed" : "skipped",
      confirmed_via: "admin",
      confirmed_at: now,
      updated_at: now,
    }).eq("id", mealConfirmationId);
    if (upErr) return json({ error: "Could not update meal" }, 500);

    // Same meals-remaining balance adjustment whatsapp-webhook does for the
    // same transition — a manager's manual yes/no must count the same as a
    // real WhatsApp reply, or the balance quietly drifts wrong.
    const wasConfirmed = meal.status === "confirmed";
    const mealsPerDay = (sub.subscription_plans?.meals_per_day as number) ?? 1;
    const delta = mealsRemainingDelta(isYes, !isYes, wasConfirmed, mealsPerDay);
    if (delta !== 0) {
      await sb.rpc("adjust_meals_remaining",
        { sub_id: meal.subscription_id, delta });
    }

    let acked = false;
    const cfg = await loadWhatsAppConfig(sb);
    if (cfg && sub.phone) {
      const tpl = await loadTemplate(sb, isYes ? "confirm_ack" : "skip_ack");
      if (tpl) {
        const r = await sendWhatsAppText(cfg, toWaNumber(sub.phone), renderTemplate(tpl, {
          name: sub.customer_name || "there",
          date: prettyDate(meal.meal_date),
        }));
        acked = r.ok;
      }
    }

    return json({ ok: true, acked });
  } catch (e) {
    console.error("admin-confirm-meal error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
