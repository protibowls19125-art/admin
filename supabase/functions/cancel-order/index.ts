import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Lets a guest customer cancel their own order, using the order's own UUID as
// the only proof of access — same pattern as get-order-status, since there's
// no customer login in this app. Only allowed while the order is still
// pending; once the kitchen has confirmed it (or moved it further along),
// cancellation is rejected. The status is always read from the DB — the
// client's belief about its own order's status is never trusted.

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

const CANCELLABLE = ["pending"];

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const UUID_RE =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const body = await req.json();
    const orderId = String(body?.orderId ?? "").trim();
    if (!UUID_RE.test(orderId)) return json({ error: "Invalid order id" }, 400);

    const { data: order, error: fetchErr } = await sb.from("orders")
      .select("id,status")
      .eq("id", orderId)
      .maybeSingle();
    if (fetchErr) return json({ error: "Lookup failed" }, 500);
    if (!order) return json({ error: "Order not found" }, 404);

    if (!CANCELLABLE.includes(order.status)) {
      return json({
        cancelled: false,
        status: order.status,
        error: order.status === "cancelled"
          ? "This order is already cancelled."
          : "This order has already been confirmed by the kitchen and can no longer be cancelled.",
      });
    }

    // Re-check the status in the UPDATE's own WHERE clause (not just the read
    // above) so a status change landing between our read and write — e.g. the
    // kitchen accepting it at that exact moment — can't be raced past.
    const { data: updated, error: updateErr } = await sb.from("orders")
      .update({ status: "cancelled" })
      .eq("id", orderId)
      .in("status", CANCELLABLE)
      .select("id");
    if (updateErr) return json({ error: "Cancel failed" }, 500);

    if (!updated || updated.length === 0) {
      const { data: fresh } = await sb.from("orders")
        .select("status").eq("id", orderId).maybeSingle();
      return json({
        cancelled: false,
        status: fresh?.status ?? order.status,
        error: "This order can no longer be cancelled.",
      });
    }

    return json({ cancelled: true, status: "cancelled" });
  } catch (e) {
    console.error("cancel-order error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
