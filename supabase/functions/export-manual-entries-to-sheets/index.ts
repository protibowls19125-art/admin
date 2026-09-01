import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Daily job: appends not-yet-exported manual_subscription_entries to a
// Google Sheet (same Apps Script Web App webhook as export-orders-to-sheets /
// export-subscription-meals-to-sheets, routed to its own tab via the "sheet"
// field). Rows are never pruned — unlike orders/meals this is a low-volume
// paper trail the admin panel keeps showing indefinitely, only the sheet
// mirror is best-effort.
//
// Columns: date, name, phone, plan, amount, notes, added by.
//
// Callable by:
//   • pg_cron          → header  x-cron-secret: <CRON_SECRET env>
//   • the admin panel  → Authorization: Bearer <admin/developer/sub_manager JWT>

const BATCH_SIZE = 500; // per run, so one huge backlog can't time the function out

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

    const { data: rows, error: qErr } = await sb.from("manual_subscription_entries")
      .select("id, customer_name, phone, plan_name, amount, notes, added_by, created_at")
      .eq("synced_to_sheet", false)
      .order("created_at", { ascending: true })
      .limit(BATCH_SIZE);
    if (qErr) return json({ error: "Lookup failed: " + qErr.message }, 500);

    let exported = 0;
    if (rows && rows.length > 0) {
      const sheetRows = rows.map((r: any) => [
        (r.created_at ?? "").toString().slice(0, 10),
        r.customer_name ?? "",
        r.phone ?? "",
        r.plan_name ?? "",
        r.amount ?? "",
        r.notes ?? "",
        r.added_by ?? "",
      ]);

      const hookRes = await fetch(webhookUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          secret: webhookSecret,
          sheet: "Sheet3",
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
      const { error: updErr } = await sb.from("manual_subscription_entries")
        .update({ synced_to_sheet: true }).in("id", ids);
      if (updErr) {
        return json({ error: "Rows appended to sheet but marking synced failed: " + updErr.message }, 500);
      }
      exported = rows.length;
    }

    return json({ exported });
  } catch (e) {
    console.error("export-manual-entries-to-sheets error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
