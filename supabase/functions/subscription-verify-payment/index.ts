import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hmacHex } from "../_shared/security.ts";

// Verifies the Razorpay signature for a SUBSCRIPTION payment and moves the
// skeleton row awaiting_payment -> payment_received. The onboarding details
// arrive afterwards via subscription-submit-details.

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
    const verified = expected === sig;

    const { data: sub } = await sb.from("subscriptions")
      .select("id,status,plan_id, subscription_plans(price,name)")
      .eq("razorpay_order_id", oid)
      .maybeSingle();
    if (!sub)
      return json({ verified, error: "Subscription not found" }, verified ? 404 : 400);

    if (!verified) {
      // Monitoring: a bad signature can mean a forged-payment attempt.
      try {
        await sb.from("audit_log").insert({
          event: "sub_payment_verify_fail",
          detail: { razorpay_order_id: oid, payment_id: pid },
        });
      } catch (_) { /* non-fatal */ }
      return json({ verified: false });
    }

    // Finalize only once (idempotent on retries).
    if (sub.status === "awaiting_payment") {
      const plan = (sub as any).subscription_plans;
      await sb.from("subscriptions").update({
        status: "payment_received",
        razorpay_payment_id: pid,
        amount_paid: plan ? Number(plan.price) : null,
        updated_at: new Date().toISOString(),
      }).eq("id", sub.id);
    }

    return json({ verified: true, subscriptionId: sub.id });
  } catch (e) {
    console.error("subscription-verify-payment error:", e);
    return json(
      { verified: false, error: e instanceof Error ? e.message : "Unknown error" },
      500,
    );
  }
});
