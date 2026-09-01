import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hmacHex, timingSafeEqual } from "../_shared/security.ts";

// Server-to-server reconciliation webhook.
// Handles:
// 1. Restaurant Orders (payment.captured / order.paid)
// 2. Meal Delivery On-the-Spot QR & Payment Links (notes.meal_id)
// 3. Subscriptions / Gym Memberships
//
// Configure in Razorpay Dashboard -> Settings -> Webhooks:
//   URL:    https://esiatypehvnyeemvnzbl.supabase.co/functions/v1/razorpay-webhook
//   Secret: same value as the RAZORPAY_WEBHOOK_SECRET function secret below
//   Events: payment.captured, payment.failed, payment_link.paid, qr_code.credited

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: { "Content-Type": "application/json", "X-Content-Type-Options": "nosniff" },
  });

// deno-lint-ignore no-explicit-any
async function finalizeDeliveryPaid(sb: any, mealId: string, manualEntryId: string, amount: number, paymentId: string) {
  const now = new Date().toISOString();
  try {
    await sb.from("meal_confirmations").update({
      payment_method: "online",
      payment_status: "paid",
      payment_amount: amount,
      payment_collected_at: now,
      status: "delivered",
      delivered_at: now,
    }).eq("id", mealId);

    if (manualEntryId) {
      await sb.from("manual_subscription_entries").update({
        payment_status: "paid",
        payment_method: "online",
        amount: amount,
      }).eq("id", manualEntryId);
    }
  } catch (e) {
    console.error("finalizeDeliveryPaid error:", e);
  }
}

// deno-lint-ignore no-explicit-any
async function finalizePaid(sb: any, razorpayOrderId: string, paymentId: string) {
  const { data: order } = await sb.from("orders")
    .select("id,status,customer_info,items")
    .eq("razorpay_order_id", razorpayOrderId)
    .maybeSingle();
  if (!order || order.status !== "awaiting_payment") return;

  const ci = (order.customer_info ?? {}) as Record<string, unknown>;
  ci.payment = {
    provider: "razorpay", status: "paid",
    payment_id: paymentId, order_id: razorpayOrderId, via: "webhook",
  };
  await sb.from("orders").update({ status: "pending", customer_info: ci }).eq("id", order.id);

  const today = new Date().toISOString().slice(0, 10);
  const qty = new Map<string, number>();
  // deno-lint-ignore no-explicit-any
  for (const it of (order.items ?? []) as any[]) {
    const id = it.menu_item_id;
    if (id) qty.set(id, (qty.get(id) ?? 0) + (Number(it.quantity) || 1));
  }
  for (const [id, q] of qty) {
    try {
      await sb.rpc("increment_item_order_count", { p_item_id: id, p_quantity: q, p_date: today });
    } catch (_) { /* non-fatal */ }
  }
}

// deno-lint-ignore no-explicit-any
async function markFailed(sb: any, razorpayOrderId: string) {
  const { data: order } = await sb.from("orders")
    .select("id,status").eq("razorpay_order_id", razorpayOrderId).maybeSingle();
  if (order && order.status === "awaiting_payment") {
    await sb.from("orders").update({ status: "payment_failed" }).eq("id", order.id);
  }
}

serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
    if (!url || !serviceKey || !webhookSecret) return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const raw = await req.text();
    const given = req.headers.get("x-razorpay-signature") ?? "";
    const expected = await hmacHex(raw, webhookSecret);
    if (!timingSafeEqual(given, expected)) {
      try {
        await sb.from("audit_log").insert({ event: "razorpay_webhook_bad_signature", detail: {} });
      } catch (_) { /* non-fatal */ }
      return json({ error: "Bad signature" }, 400);
    }

    const payload = JSON.parse(raw || "{}");
    const event = payload.event as string;
    const payment = payload.payload?.payment?.entity;
    const paymentLink = payload.payload?.payment_link?.entity;
    const qrCode = payload.payload?.qr_code?.entity;

    // Check if this payment is for a Delivery Meal Order
    const notes = payment?.notes ?? paymentLink?.notes ?? qrCode?.notes ?? {};
    const mealId = notes.meal_id as string | undefined;
    const manualEntryId = (notes.manual_entry_id as string | undefined) ?? "";

    if (mealId) {
      const amountPaise = payment?.amount ?? paymentLink?.amount ?? qrCode?.payment_amount ?? 0;
      const amount = Number(amountPaise) / 100;
      const paymentId = payment?.id ?? paymentLink?.id ?? qrCode?.id ?? "rzp_webhook";
      await finalizeDeliveryPaid(sb, mealId, manualEntryId, amount, paymentId);
      return json({ ok: true, handled: "delivery_payment" });
    }

    // Standard Restaurant Order webhook handling
    if (event === "payment.captured" || event === "order.paid") {
      const orderId = payment?.order_id ?? payload.payload?.order?.entity?.id;
      if (orderId) await finalizePaid(sb, orderId, payment?.id ?? "");
    } else if (event === "payment.failed") {
      if (payment?.order_id) await markFailed(sb, payment.order_id);
    }

    return json({ ok: true });
  } catch (e) {
    console.error("razorpay-webhook error:", e);
    return json({ ok: false }, 500);
  }
});
