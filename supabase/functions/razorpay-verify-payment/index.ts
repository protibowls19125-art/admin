import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hmacHex, timingSafeEqual } from "../_shared/security.ts";

// Verifies the Razorpay payment signature and FINALIZES the matching pending
// order (awaiting_payment -> pending). The amount is trustworthy because the
// Razorpay order was created server-side for the DB-computed total, and the
// signature proves this payment is for that exact order.

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
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!url || !serviceKey || !keySecret)
      return json({ verified: false, error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const {
      razorpay_order_id: oid,
      razorpay_payment_id: pid,
      razorpay_signature: sig,
    } = await req.json();
    if (!oid || !pid || !sig)
      return json({ verified: false, error: "Missing fields" }, 400);

    const expected = await hmacHex(`${oid}|${pid}`, keySecret);
    const verified = timingSafeEqual(expected, sig);

    const { data: order } = await sb.from("orders")
      .select("id,order_number,items,total_price,customer_info,status")
      .eq("razorpay_order_id", oid)
      .maybeSingle();

    if (!order)
      return json({ verified, error: "Order not found" }, verified ? 404 : 400);

    if (!verified) {
      if (order.status === "awaiting_payment") {
        await sb.from("orders").update({ status: "payment_failed" }).eq("id", order.id);
      }
      // Monitoring: a bad signature can mean a forged-payment attempt.
      try {
        await sb.from("audit_log").insert({
          event: "payment_verify_fail",
          detail: { razorpay_order_id: oid, payment_id: pid },
        });
      } catch (_) { /* non-fatal */ }
      return json({ verified: false });
    }

    // Finalize only once (idempotent on retries).
    if (order.status === "awaiting_payment") {
      const ci = (order.customer_info ?? {}) as Record<string, unknown>;
      ci.payment = { provider: "razorpay", status: "paid", payment_id: pid, order_id: oid };
      await sb.from("orders")
        .update({ status: "pending", customer_info: ci })
        .eq("id", order.id);

      // Count toward daily limits now that it's actually paid.
      const today = new Date().toISOString().slice(0, 10);
      const qty = new Map<string, number>();
      for (const it of (order.items ?? []) as any[]) {
        const id = it.menu_item_id;
        if (id) qty.set(id, (qty.get(id) ?? 0) + (Number(it.quantity) || 1));
      }
      for (const [id, q] of qty) {
        try {
          await sb.rpc("increment_item_order_count",
            { p_item_id: id, p_quantity: q, p_date: today });
        } catch (_) { /* non-fatal */ }
      }
    }

    return json({
      verified: true,
      dbOrderId: order.id,
      orderNumber: order.order_number,
      totalPrice: order.total_price,
      items: order.items,
    });
  } catch (e) {
    console.error("verify-payment error:", e);
    return json({ verified: false, error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
