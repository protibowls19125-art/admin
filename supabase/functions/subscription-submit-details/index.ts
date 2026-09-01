import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Attaches the onboarding answers (name, phone, preference, health goal,
// address) to a PAID subscription and moves it to pending_approval, where the
// manager reviews it. Possession of the matching razorpay order id + payment
// id (returned only to the payer's browser) acts as the bearer proof — there
// is no logged-in user yet at this point.

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

const GOALS = ["weight_loss", "muscle_gain", "balanced_nutrition",
  "diabetic_friendly", "general_fitness"];

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const body = await req.json();
    const oid = String(body.razorpay_order_id ?? "").trim();
    const pid = String(body.razorpay_payment_id ?? "").trim();
    const name = String(body.customer_name ?? "").trim().slice(0, 120);
    const phone = String(body.phone ?? "").replace(/[^\d+]/g, "").slice(0, 15);
    const email = String(body.email ?? "").trim().toLowerCase().slice(0, 254);
    const pref = String(body.food_preference ?? "").trim();
    const goal = String(body.health_goal ?? "").trim();
    const notes = String(body.health_notes ?? "").trim().slice(0, 1000);
    const address = body.delivery_address && typeof body.delivery_address === "object"
      ? body.delivery_address
      : {};

    if (!oid || !pid) return json({ error: "Missing payment reference" }, 400);
    if (!name || phone.replace(/\D/g, "").length < 10)
      return json({ error: "Name and a valid mobile number are required" }, 400);
    // Admin-editable (food_preferences table), not a hardcoded list — the
    // manager can add/remove options from Admin panel without a redeploy.
    const { data: prefRows } = await sb.from("food_preferences")
      .select("key").eq("active", true);
    const validPrefs = (prefRows ?? []).map((r) => r.key as string);
    if (!validPrefs.includes(pref)) return json({ error: "Invalid food preference" }, 400);
    if (!GOALS.includes(goal)) return json({ error: "Invalid health goal" }, 400);

    // The row must exist, be paid, and the payment id must match what the
    // verify step recorded — that pair never leaves the payer's session.
    const { data: sub } = await sb.from("subscriptions")
      .select("id,status,razorpay_payment_id")
      .eq("razorpay_order_id", oid)
      .maybeSingle();
    if (!sub || sub.razorpay_payment_id !== pid)
      return json({ error: "Payment not found" }, 404);
    if (!["payment_received", "pending_approval"].includes(sub.status))
      return json({ error: "This subscription can no longer be edited" }, 409);

    const { error: upErr } = await sb.from("subscriptions").update({
      customer_name: name,
      phone,
      email,
      food_preference: pref,
      health_goal: goal,
      health_notes: notes,
      delivery_address: address,
      status: "pending_approval",
      updated_at: new Date().toISOString(),
    }).eq("id", sub.id);
    if (upErr) return json({ error: "Could not save details" }, 500);

    return json({ ok: true, subscriptionId: sub.id, status: "pending_approval" });
  } catch (e) {
    console.error("subscription-submit-details error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
