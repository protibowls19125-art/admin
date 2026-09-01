import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Daily job: appends not-yet-exported orders to a Google Sheet (via an Apps
// Script Web App webhook — no Google Cloud project/service account needed),
// then deletes from Supabase any order that's already synced_to_sheet = true
// — same-day retention, keeps Supabase storage flat, full order history
// lives only in the Sheet from here on. A row is never deleted before it's
// confirmed synced, so a failed webhook call just retries next run rather
// than losing data.
//
// same-day retention means agent_performance_page's week/month delivery
// totals (which read up to 45 days of `orders`) will only ever see today —
// known, accepted trade-off, not a bug.
//
// Callable by:
//   • pg_cron          → header  x-cron-secret: <CRON_SECRET env>
//   • the admin panel  → Authorization: Bearer <admin/developer JWT>

const ORDER_RETENTION_DAYS = 0;
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

    // ── AuthZ: cron secret OR an admin/developer JWT ──────────────────────
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
          authorized = ["admin", "developer"].includes(profile?.role ?? "");
        }
      }
    }
    if (!authorized) return json({ error: "Not authorized" }, 401);

    const webhookUrl = Deno.env.get("SHEETS_WEBHOOK_URL");
    const webhookSecret = Deno.env.get("SHEETS_WEBHOOK_SECRET");
    if (!webhookUrl || !webhookSecret) {
      return json({ error: "Sheets webhook not configured" }, 500);
    }

    // ── 1. Pull the not-yet-exported backlog ───────────────────────────────
    const { data: orders, error: qErr } = await sb.from("orders")
      .select("id, order_number, created_at, order_type, payment_method, status, customer_name, customer_phone, total_price, customer_info, items")
      .eq("synced_to_sheet", false)
      .order("created_at", { ascending: true })
      .limit(BATCH_SIZE);
    if (qErr) return json({ error: "Order lookup failed: " + qErr.message }, 500);

    let exported = 0;
    if (orders && orders.length > 0) {
      const rows = orders.map((o: any) => {
        const items = Array.isArray(o.items)
          ? o.items.map((it: any) => `${it.name} x${it.quantity}`).join(", ")
          : "";
        const addr = (o.customer_info?.delivery_address ?? null);
        const addrStr = addr
          ? [addr.address, addr.landmark, addr.city, addr.pincode].filter(Boolean).join(", ")
          : "";
        return [
          o.order_number ?? o.id,
          o.created_at,
          o.order_type ?? "",
          o.payment_method ?? "",
          o.status ?? "",
          o.customer_name ?? "",
          o.customer_phone ?? "",
          items,
          Number(o.total_price ?? 0),
          addrStr,
        ];
      });

      const hookRes = await fetch(webhookUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ secret: webhookSecret, rows }),
      });
      const hookText = await hookRes.text();
      if (!hookRes.ok || hookText.trim() !== "ok") {
        return json({ error: "Sheet webhook failed: " + hookText }, 502);
      }

      // Only mark synced AFTER the webhook confirms — never the other way
      // around, or a failed write could still get pruned later.
      const ids = orders.map((o: any) => o.id);
      const { error: updErr } = await sb.from("orders")
        .update({ synced_to_sheet: true }).in("id", ids);
      if (updErr) {
        return json({ error: "Rows appended to sheet but marking synced failed: " + updErr.message }, 500);
      }
      exported = orders.length;
    }

    // ── 2. Prune synced orders past the retention window ───────────────────
    const cutoff = new Date(Date.now() - ORDER_RETENTION_DAYS * 86_400_000).toISOString();
    const { data: pruned, error: delErr } = await sb.from("orders")
      .delete()
      .eq("synced_to_sheet", true)
      .lt("created_at", cutoff)
      .select("id");
    if (delErr) return json({ error: "Prune failed: " + delErr.message }, 500);

    return json({ exported, pruned: pruned?.length ?? 0, retentionDays: ORDER_RETENTION_DAYS });
  } catch (e) {
    console.error("export-orders-to-sheets error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
