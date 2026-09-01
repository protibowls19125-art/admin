import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Creates a Razorpay order for a subscription PLAN. The price comes from the
// DB (subscription_plans) — the client only sends a plan id, never an amount.
// A skeleton `subscriptions` row (awaiting_payment) is stored so the payment
// can be reconciled even if the customer abandons the onboarding form.

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
    const rzpId = Deno.env.get("RAZORPAY_KEY_ID");
    const rzpSecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    if (!rzpId || !rzpSecret) return json({ error: "Razorpay not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const body = await req.json();
    const planId = String(body.plan_id ?? "").trim();
    if (!planId) return json({ error: "Missing plan" }, 400);

    // Anti-flood: reuse the order rate limiter keyed on IP (best-effort).
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() ||
      req.headers.get("cf-connecting-ip") || "unknown";
    const windowStart = new Date(Date.now() - 15 * 60_000).toISOString();
    try {
      const { count } = await sb.from("order_rate_limit")
        .select("*", { count: "exact", head: true })
        .eq("ip", ip).gte("created_at", windowStart);
      if ((count ?? 0) >= 12) {
        return json({ error: "Too many attempts. Please wait a few minutes." }, 429);
      }
      await sb.from("order_rate_limit").insert({ ip, phone: "subscription" });
    } catch (_) { /* fail open */ }

    // Authoritative price from the DB.
    const { data: plan, error: planErr } = await sb
      .from("subscription_plans")
      .select("id,name,price,duration_days,meals_per_day,active")
      .eq("id", planId)
      .maybeSingle();
    if (planErr || !plan) return json({ error: "Plan not found" }, 404);
    if (plan.active === false) return json({ error: "Plan is not available" }, 409);

    const amountPaise = Math.round(Number(plan.price) * 100);
    if (amountPaise <= 0) return json({ error: "Invalid plan price" }, 400);

    const auth = "Basic " + btoa(`${rzpId}:${rzpSecret}`);
    const rzpRes = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: { Authorization: auth, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount: amountPaise,
        currency: "INR",
        receipt: `sub_${Date.now()}`,
        payment_capture: 1,
        notes: { type: "subscription", plan: plan.name },
      }),
    });
    const rzp = await rzpRes.json();
    if (!rzpRes.ok)
      return json({ error: rzp.error?.description ?? "Razorpay order failed" }, 400);

    const { data: row, error: insErr } = await sb.from("subscriptions").insert({
      plan_id: plan.id,
      status: "awaiting_payment",
      razorpay_order_id: rzp.id,
    }).select("id").single();
    if (insErr) return json({ error: "Could not start subscription" }, 500);

    return json({
      razorpayOrderId: rzp.id,
      keyId: rzpId,
      amount: amountPaise,
      currency: "INR",
      subscriptionId: row.id,
      planName: plan.name,
    });
  } catch (e) {
    console.error("subscription-create-order error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
