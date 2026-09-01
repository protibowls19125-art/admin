import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { haversineMeters } from "../_shared/geofence.ts";

// Server-side order creation. Prices are computed from the DB — the client
// NEVER sends prices or totals. For `online`, a Razorpay order is created for
// the server-computed amount and a pending order is stored; razorpay-verify-payment
// finalizes it. For `cod`, the order is stored immediately. All writes use the
// service-role key (bypasses RLS), so anon clients can't write orders directly.

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

const ORDER_TYPES = ["dine_in", "takeaway", "delivery"];

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, {
      auth: { persistSession: false },
    });

    const body = await req.json();
    const items = Array.isArray(body.items) ? body.items : [];
    const orderType = String(body.order_type ?? "");
    const paymentMethod = String(body.payment_method ?? "");
    const customerName = String(body.customer_name ?? "").trim().slice(0, 120);
    const customerPhone = String(body.customer_phone ?? "").trim().slice(0, 20);
    const deliveryAddress = body.delivery_address ?? null;

    // --- validate ---
    if (items.length === 0) return json({ error: "No items" }, 400);
    if (!customerName || !customerPhone)
      return json({ error: "Missing customer info" }, 400);
    // Phone: digits, +, spaces, hyphens only — no script/HTML injection.
    if (!/^[\d+\s\-()]{7,20}$/.test(customerPhone))
      return json({ error: "Invalid phone number format" }, 400);
    if (!ORDER_TYPES.includes(orderType))
      return json({ error: "Invalid order type" }, 400);
    // Takeaway is online-only — a no-show pickup can't be recovered the way
    // an unpaid online order can. Enforced here too since the client-side
    // toggle alone can't be trusted.
    if (orderType === "takeaway" && paymentMethod === "cod") {
      return json({ error: "Takeaway orders must be paid online" }, 400);
    }
    if (!["online", "cod", "free"].includes(paymentMethod))
      return json({ error: "Invalid payment method" }, 400);

    // --- anti-flood rate limit (anti-DoS) ---
    // Caps how many orders one IP / one phone can place in a short window.
    // Legit customers place 1–2 orders; floods get blocked. Transparent to the app.
    const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() ||
      req.headers.get("cf-connecting-ip") || "unknown";
    const WINDOW_MIN = 15;
    const MAX_PER_IP = 12;
    const MAX_PER_PHONE = 5;
    const windowStart = new Date(Date.now() - WINDOW_MIN * 60_000).toISOString();
    try {
      const { count: ipCount } = await sb.from("order_rate_limit")
        .select("*", { count: "exact", head: true })
        .eq("ip", ip).gte("created_at", windowStart);
      const { count: phoneCount } = await sb.from("order_rate_limit")
        .select("*", { count: "exact", head: true })
        .eq("phone", customerPhone).gte("created_at", windowStart);
      if ((ipCount ?? 0) >= MAX_PER_IP || (phoneCount ?? 0) >= MAX_PER_PHONE) {
        // Monitoring: record the block so admins can see flooding attempts.
        try {
          await sb.from("audit_log").insert({
            event: "rate_limit_block",
            ip,
            detail: { phone: customerPhone, ipCount, phoneCount },
          });
        } catch (_) { /* non-fatal */ }
        return json(
          { error: "Too many orders in a short time. Please wait a few minutes." },
          429,
        );
      }
    } catch (_) {
      // If the limiter table is missing/unreachable, fail OPEN so real orders
      // still go through (availability > strictness for a paying customer).
    }

    // --- authoritative price from DB ---
    const ids = [...new Set(items.map((i: any) => String(i.menu_item_id)))];
    const { data: menuRows, error: menuErr } = await sb
      .from("menu_items")
      .select("id,name,price,available,daily_limit,orders_today")
      .in("id", ids);
    if (menuErr) return json({ error: "Menu lookup failed" }, 500);
    const byId = new Map((menuRows ?? []).map((m: any) => [m.id, m]));

    let total = 0;
    const line: any[] = [];
    const qtyById = new Map<string, number>();
    for (const it of items) {
      const m = byId.get(String(it.menu_item_id));
      if (!m) return json({ error: `Item not found` }, 400);
      if (m.available === false)
        return json({ error: `${m.name} is unavailable` }, 409);
      const qty = Math.max(1, Math.min(99, parseInt(String(it.quantity)) || 1));
      if (m.daily_limit && m.daily_limit > 0 &&
          (m.orders_today ?? 0) + qty > m.daily_limit)
        return json({ error: `${m.name} is sold out` }, 409);
      total += Number(m.price) * qty;
      // note (e.g. spice level) is customer-supplied, pass-through only —
      // it never affects price/availability, those stay server-computed.
      const note = typeof it.note === "string" ? it.note.slice(0, 100) : undefined;
      line.push({
        menu_item_id: m.id, name: m.name, price: Number(m.price), quantity: qty,
        ...(note ? { note } : {}),
      });
      qtyById.set(m.id, (qtyById.get(m.id) ?? 0) + qty);
    }
    // Gold membership discount + free delivery, if the caller is logged in
    // as an active Gold member. functions.invoke() always attaches the
    // current session's Authorization header (same pattern used to verify
    // a manager's identity in admin-manage-member) — no client-side change
    // needed to "pass" membership status, it's derived from whether the
    // customer happens to be logged in at checkout.
    let goldDiscountPercent = 0;
    let goldFreeDelivery = false;
    try {
      const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
      if (jwt) {
        const { data: userData } = await sb.auth.getUser(jwt);
        if (userData?.user) {
          const today = new Date().toISOString().slice(0, 10);
          const { data: membership } = await sb.from("gym_memberships")
            .select("*, gym_membership_plans(discount_percent,free_delivery)")
            .eq("auth_user_id", userData.user.id)
            .eq("status", "active")
            .gte("end_date", today)
            .maybeSingle();
          const plan = (membership as any)?.gym_membership_plans;
          if (plan) {
            goldDiscountPercent = Number(plan.discount_percent ?? 0);
            // Independent per-plan toggle — not implied by having a
            // discount. Previously this fell through to "waived whenever
            // there's any discount", so turning free_delivery off in the
            // admin panel had no effect on the actual checkout charge.
            goldFreeDelivery = plan.free_delivery === true;
          }
        }
      }
    } catch (_) { /* not a Gold member / lookup failed — no discount */ }

    if (goldDiscountPercent > 0) {
      total = total * (1 - goldDiscountPercent / 100);
    }

    // GST (exclusive — added on top of the subtotal, after any Gold
    // discount) + delivery charge, both server-controlled from bill_config.
    // Delivery is waived only for a Gold plan with free_delivery = true
    // (per-plan admin toggle, independent of the discount); GST is not.
    let gstPercent = 0;
    let gstAmount = 0;
    let deliveryCharge = 0;
    let cfg: Record<string, unknown> = {};
    try {
      const { data: bc } = await sb.from("app_config")
        .select("value").eq("key", "bill_config").maybeSingle();
      cfg = (bc?.value as Record<string, unknown>) ?? {};
      gstPercent = Number(cfg.gst_percent ?? 0);
      if (gstPercent > 0) {
        gstAmount = total * gstPercent / 100;
        total += gstAmount;
      }
      if (!goldFreeDelivery && orderType === "delivery") {
        const fee = Number(cfg.delivery_charge ?? 0);
        if (fee > 0) {
          deliveryCharge = fee;
          total += fee;
        }
      }
    } catch (_) { /* no gst/fee */ }

    // Cash payment (any order type it's still offered on — dine_in or
    // delivery; takeaway is rejected above) requires the customer's pinned
    // location to fall inside the configured geofence. This is a contactless
    // ordering app: cash can't be verified after the fact the way an online
    // payment can, so "you must be here to pay cash" is checked for every
    // order type, not just delivery. An admin must flip cod_geofence_enabled
    // on and set cod_center_lat/lng + cod_radius_m (meters) in bill_config.
    // Authoritative here (not just the client) since a modified client could
    // otherwise skip the location pin entirely.
    if (paymentMethod === "cod") {
      if (cfg.cod_geofence_enabled !== true) {
        return json({ error: "Cash payment isn't available right now" }, 400);
      }
      const centerLat = Number(cfg.cod_center_lat);
      const centerLng = Number(cfg.cod_center_lng);
      const radiusM = Number(cfg.cod_radius_m ?? 0);
      if (!radiusM || !Number.isFinite(centerLat) || !Number.isFinite(centerLng)) {
        return json({ error: "Cash payment isn't available right now" }, 400);
      }
      const custLat = Number((deliveryAddress as Record<string, unknown> | null)?.latitude);
      const custLng = Number((deliveryAddress as Record<string, unknown> | null)?.longitude);
      if (!Number.isFinite(custLat) || !Number.isFinite(custLng)) {
        return json({ error: "Please confirm your location on the map to pay by cash" }, 400);
      }
      if (haversineMeters(centerLat, centerLng, custLat, custLng) > radiusM) {
        return json({ error: "You're too far away to pay by cash — please pay online" }, 400);
      }
    }

    if (total <= 0 && paymentMethod !== "free") return json({ error: "Invalid total" }, 400);

    // Record this attempt for the rate limiter (best-effort), and opportunistically
    // prune old rows so the table stays tiny.
    try {
      await sb.from("order_rate_limit").insert({ ip, phone: customerPhone });
      if (Math.random() < 0.05) {
        await sb.from("order_rate_limit").delete().lt("created_at", windowStart);
      }
    } catch (_) { /* non-fatal */ }

    const amountPaise = Math.round(total * 100);
    const createdAt = new Date().toISOString();
    const customerInfo: Record<string, unknown> = {
      name: customerName, phone: customerPhone, order_type: orderType,
    };
    if (deliveryAddress) customerInfo.delivery_address = deliveryAddress;
    if (goldDiscountPercent > 0) {
      customerInfo.gold_discount_percent = goldDiscountPercent;
    }
    if (gstAmount > 0) {
      // Recorded exactly as charged, so the e-bill reflects the rate at
      // order time even if bill_config's gst_percent changes later.
      customerInfo.gst_percent = gstPercent;
      customerInfo.gst_amount = Math.round(gstAmount * 100) / 100;
    }
    if (deliveryCharge > 0) {
      // Recorded explicitly (not left for the e-bill to infer from
      // total − subtotal − GST) — that subtraction has no order_type check
      // and misattributes GST rounding noise as a phantom delivery charge
      // on dine-in/takeaway bills.
      customerInfo.delivery_charge = deliveryCharge;
    }

    // Sequential 6-digit order number (RPC if present; else trigger handles it).
    let orderNumber: string | undefined;
    try {
      const { data: n } = await sb.rpc("get_next_order_number");
      const s = String(n ?? "").trim();
      if (s.length === 6) orderNumber = s;
    } catch (_) { /* trigger will set it */ }

    const baseRow: Record<string, unknown> = {
      order_type: orderType,
      customer_name: customerName,
      customer_phone: customerPhone,
      total_price: total,
      customer_info: customerInfo,
      items: line,
      created_at: createdAt,
    };
    if (orderNumber) baseRow.order_number = orderNumber;

    if (paymentMethod === "online") {
      // ── Free orders: total is ₹0, skip Razorpay entirely ──────────────
      if (total <= 0) {
        return json({ error: "Cannot process online payment for a free order — use free payment method" }, 400);
      }
      const rzpId = Deno.env.get("RAZORPAY_KEY_ID");
      const rzpSecret = Deno.env.get("RAZORPAY_KEY_SECRET");
      if (!rzpId || !rzpSecret)
        return json({ error: "Razorpay not configured" }, 500);

      const auth = "Basic " + btoa(`${rzpId}:${rzpSecret}`);
      const rzpRes = await fetch("https://api.razorpay.com/v1/orders", {
        method: "POST",
        headers: { Authorization: auth, "Content-Type": "application/json" },
        body: JSON.stringify({
          amount: amountPaise, currency: "INR",
          receipt: `rcpt_${Date.now()}`, payment_capture: 1,
        }),
      });
      const rzp = await rzpRes.json();
      if (!rzpRes.ok)
        return json({ error: rzp.error?.description ?? "Razorpay order failed" }, 400);

      const { data: row, error: insErr } = await sb.from("orders").insert({
        ...baseRow,
        payment_method: "online",
        status: "awaiting_payment",
        razorpay_order_id: rzp.id,
      }).select("id, order_number").single();
      if (insErr) return json({ error: "Could not create order" }, 500);
      await insertItems(sb, row.id, line);

      return json({
        mode: "online",
        razorpayOrderId: rzp.id, keyId: rzpId, amount: amountPaise, currency: "INR",
        dbOrderId: row.id, orderNumber: row.order_number,
        totalPrice: total, items: line,
      });
    }

    // ── Free order (total = ₹0) ── same as COD but payment_method = "free"
    if (paymentMethod === "free") {
      if (total > 0) {
        return json({ error: "Free payment is only for ₹0 orders" }, 400);
      }
      const { data: row, error: insErr } = await sb.from("orders").insert({
        ...baseRow, payment_method: "free", status: "pending",
      }).select("id, order_number").single();
      if (insErr) return json({ error: "Could not create order" }, 500);
      await insertItems(sb, row.id, line);
      await bumpDaily(sb, qtyById);

      return json({
        mode: "free",
        dbOrderId: row.id, orderNumber: row.order_number,
        totalPrice: 0, items: line,
      });
    }

    // COD
    const { data: row, error: insErr } = await sb.from("orders").insert({
      ...baseRow, payment_method: "cod", status: "pending",
    }).select("id, order_number").single();
    if (insErr) return json({ error: "Could not create order" }, 500);
    await insertItems(sb, row.id, line);
    await bumpDaily(sb, qtyById);

    return json({
      mode: "cod",
      dbOrderId: row.id, orderNumber: row.order_number,
      totalPrice: total, items: line,
    });
  } catch (e) {
    console.error("create-order error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});

async function insertItems(sb: any, orderId: string, line: any[]) {
  try {
    await sb.from("order_items").insert(line.map((l) => ({
      order_id: orderId, menu_item_id: l.menu_item_id,
      name: l.name, quantity: l.quantity, price: l.price,
    })));
  } catch (_) { /* non-fatal */ }
}

async function bumpDaily(sb: any, qtyById: Map<string, number>) {
  const today = new Date().toISOString().slice(0, 10);
  for (const [id, qty] of qtyById) {
    try {
      await sb.rpc("increment_item_order_count",
        { p_item_id: id, p_quantity: qty, p_date: today });
    } catch (_) { /* non-fatal */ }
  }
}
