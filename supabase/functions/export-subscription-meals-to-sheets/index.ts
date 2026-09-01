import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { istDate } from "../_shared/whatsapp.ts";

// Daily job: appends not-yet-exported meal_confirmations to a Google Sheet
// (same Apps Script Web App webhook as export-orders-to-sheets, routed to a
// different tab via the "sheet" field in the payload), then prunes synced
// rows same-day — same free-tier-storage motivation as
// export-orders-to-sheets. A row only becomes eligible once its meal_date is
// no longer today (see the query below), so "same-day retention" here means
// "gone as soon as that day is closed out and synced", not mid-day deletion
// of a day still in progress on the KDS.
//
// same-day retention means agent_performance_page's week/month delivery
// totals AND the KDS/Survey Responses date pickers will only ever see
// today — known, accepted trade-off, not a bug.
//
// Columns: date, member, phone, member code, plan, responded (YES/NO/NO
// RESPONSE), their raw reply, dish sent, meals remaining.
//
// Callable by:
//   • pg_cron          → header  x-cron-secret: <CRON_SECRET env>
//   • the admin panel  → Authorization: Bearer <admin/developer/sub_manager JWT>

const BATCH_SIZE = 500; // per run, so one huge backlog can't time the function out
const CONFIRMED_LIKE = ["confirmed", "preparing", "prepared", "out_for_delivery", "delivered"];
const MEAL_RETENTION_DAYS = 0;

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

    // ── AuthZ: cron secret OR an admin/developer/sub_manager JWT ────────────
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

    const webhookUrl = Deno.env.get("SHEETS_WEBHOOK_URL");
    const webhookSecret = Deno.env.get("SHEETS_WEBHOOK_SECRET");
    if (!webhookUrl || !webhookSecret) {
      return json({ error: "Sheets webhook not configured" }, 500);
    }

    // ── 1. Pull the not-yet-exported backlog (any day up to yesterday — the
    // day a row belongs to is only "closed" once it's no longer today) ──────
    const { data: rows, error: qErr } = await sb.from("meal_confirmations")
      .select("id, meal_date, status, reply_text, selected_dish_ids, meal_id, "
        + "subscription_meals(name), "
        + "subscriptions(customer_name,phone,member_code,meals_remaining,subscription_plans(name))")
      .eq("synced_to_sheet", false)
      .lte("meal_date", istDate(-1))
      .order("meal_date", { ascending: true })
      .limit(BATCH_SIZE);
    if (qErr) return json({ error: "Meal lookup failed: " + qErr.message }, 500);

    let exported = 0;
    if (rows && rows.length > 0) {
      // Resolve selected_dish_ids (jsonb array of subscription_meals ids) to
      // names in one lookup rather than per-row.
      const { data: dishRows } = await sb.from("subscription_meals").select("id,name");
      const dishNameById = new Map((dishRows ?? []).map((d: any) => [d.id, d.name]));

      const sheetRows = rows.map((r: any) => {
        const sub = r.subscriptions ?? {};
        const plan = sub.subscription_plans ?? {};
        const responded = CONFIRMED_LIKE.includes(r.status)
          ? "YES"
          : r.status === "skipped"
          ? "NO"
          : "NO RESPONSE";
        const dishIds: string[] = Array.isArray(r.selected_dish_ids) ? r.selected_dish_ids : [];
        const dishNames = dishIds.map((id) => dishNameById.get(id)).filter(Boolean);
        const dishSent = dishNames.length > 0
          ? dishNames.join(", ")
          : (r.subscription_meals?.name ?? "");
        return [
          r.meal_date,
          sub.customer_name ?? "",
          sub.phone ?? "",
          sub.member_code ?? "",
          plan.name ?? "",
          responded,
          r.reply_text ?? "",
          dishSent,
          sub.meals_remaining ?? "",
        ];
      });

      const hookRes = await fetch(webhookUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          secret: webhookSecret,
          sheet: "Sheet2",
          rows: sheetRows,
        }),
      });
      const hookText = await hookRes.text();
      if (!hookRes.ok || hookText.trim() !== "ok") {
        return json({ error: "Sheet webhook failed: " + hookText }, 502);
      }

      // Only mark synced AFTER the webhook confirms — never the other way
      // around, or a failed write could still get skipped next run.
      const ids = rows.map((r: any) => r.id);
      const { error: updErr } = await sb.from("meal_confirmations")
        .update({ synced_to_sheet: true }).in("id", ids);
      if (updErr) {
        return json({ error: "Rows appended to sheet but marking synced failed: " + updErr.message }, 500);
      }
      exported = rows.length;
    }

    // ── 2. Prune synced rows past the retention window ──────────────────────
    const cutoff = istDate(-MEAL_RETENTION_DAYS);
    const { data: pruned, error: delErr } = await sb.from("meal_confirmations")
      .delete()
      .eq("synced_to_sheet", true)
      .lt("meal_date", cutoff)
      .select("id");
    if (delErr) return json({ error: "Prune failed: " + delErr.message }, 500);

    return json({ exported, pruned: pruned?.length ?? 0, retentionDays: MEAL_RETENTION_DAYS });
  } catch (e) {
    console.error("export-subscription-meals-to-sheets error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
