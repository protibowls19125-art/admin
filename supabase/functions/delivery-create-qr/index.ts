import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Edge Function: delivery-create-qr
// Creates a dynamic Razorpay QR Code / Payment Link for on-the-spot meal delivery payment.
// The delivery agent's mobile app displays the dynamic QR code for the customer to scan with any UPI app.
// Razorpay webhook automatically marks the order as paid & delivered upon payment.captured.

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

    if (!url || !serviceKey) return json({ error: "Supabase server not configured" }, 500);
    if (!rzpId || !rzpSecret) return json({ error: "Razorpay not configured on server" }, 500);

    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });
    const body = await req.json();

    const mealId = String(body.meal_id ?? "").trim();
    const amount = Number(body.amount ?? 0);
    const customerName = String(body.customer_name ?? "Customer").trim();
    const phone = String(body.phone ?? "").replace(/[^0-9]/g, "").slice(-10);
    const manualEntryId = String(body.manual_entry_id ?? "").trim();

    if (!mealId) return json({ error: "Missing meal_id" }, 400);
    if (amount <= 0) return json({ error: "Invalid amount" }, 400);

    const amountPaise = Math.round(amount * 100);
    const auth = "Basic " + btoa(`${rzpId}:${rzpSecret}`);

    let qrImageUrl = "";
    let upiPayload = "";
    let shortUrl = "";
    let referenceId = "";

    // 1. Try Razorpay Dynamic QR Code API first
    try {
      const qrRes = await fetch("https://api.razorpay.com/v1/payments/qr_codes", {
        method: "POST",
        headers: { Authorization: auth, "Content-Type": "application/json" },
        body: JSON.stringify({
          type: "upi_qr",
          name: "Proti Bowls",
          usage: "single_use",
          fixed_amount: true,
          payment_amount: amountPaise,
          description: `Delivery Payment for Meal #${mealId.slice(0, 8)}`,
          notes: {
            meal_id: mealId,
            manual_entry_id: manualEntryId || "",
            order_type: "subscription_delivery",
          },
        }),
      });

      const qrData = await qrRes.json();
      if (qrRes.ok && qrData.image_url) {
        qrImageUrl = qrData.image_url;
        upiPayload = qrData.payload_text || "";
        referenceId = qrData.id || "";
      }
    } catch (_) {
      // Fall through to Payment Link if QR Code API is not active on Razorpay account
    }

    // 2. Create Razorpay Payment Link (always supported & provides UPI QR + direct checkout link)
    const linkRes = await fetch("https://api.razorpay.com/v1/payment_links", {
      method: "POST",
      headers: { Authorization: auth, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount: amountPaise,
        currency: "INR",
        accept_partial: false,
        description: `Proti Bowls Meal Delivery - ${customerName}`,
        customer: {
          name: customerName,
          contact: phone ? `+91${phone}` : undefined,
        },
        notify: {
          sms: false,
          email: false,
        },
        reminder_enable: false,
        notes: {
          meal_id: mealId,
          manual_entry_id: manualEntryId || "",
          order_type: "subscription_delivery",
        },
        upi_link: true,
      }),
    });

    const linkData = await linkRes.json();
    if (linkRes.ok && linkData.short_url) {
      shortUrl = linkData.short_url;
      if (!referenceId) referenceId = linkData.id;
      // Use Razorpay's official secure checkout link as the QR payload
      if (!upiPayload) {
        upiPayload = shortUrl;
      }
    } else if (!qrImageUrl && !upiPayload) {
      return json({
        error: linkData.error?.description ?? "Could not generate Razorpay payment link",
      }, 400);
    }

    // 3. Store reference in meal_confirmations
    try {
      await sb.from("meal_confirmations").update({
        payment_amount: amount,
      }).eq("id", mealId);
    } catch (_) {}

    return json({
      success: true,
      meal_id: mealId,
      amount: amount,
      qr_image_url: qrImageUrl,
      upi_payload: upiPayload,
      payment_link: shortUrl,
      reference_id: referenceId,
      key_id: rzpId,
    });
  } catch (e) {
    console.error("delivery-create-qr error:", e);
    return json({ error: e instanceof Error ? e.message : "Internal server error" }, 500);
  }
});
