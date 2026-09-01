import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hmacHex, timingSafeEqual } from "../_shared/security.ts";

// Self-service Gold membership activation — fired right after a successful
// Razorpay checkout callback, with the customer's own chosen email+password
// (there's no manager review step for Gold, unlike Elite/subscriptions: a
// membership is a discount flag, not a meal-planning commitment for someone
// to check). Verifies the payment signature itself, folding what
// subscription-verify-payment + admin-manage-member's approve action do
// separately (for Elite) into one call — Gold never needed the extra
// manual-approval round trip.
//
// Idempotent/re-enterable: if the customer pays, closes the tab before
// finishing this step, and comes back later, calling this again with the
// same razorpay ids just returns the existing membership rather than
// erroring — there's no manager to rescue a stuck row the way there is for
// subscriptions, so this path has to be safe to retry standalone.

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

/** yyyy-mm-dd for "today + offsetDays" in IST. */
function istDate(offsetDays = 0): string {
  const ist = new Date(Date.now() + (5.5 * 60 + offsetDays * 24 * 60) * 60_000);
  return ist.toISOString().slice(0, 10);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
    if (!url || !serviceKey || !keySecret)
      return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const {
      razorpay_order_id: oid,
      razorpay_payment_id: pid,
      razorpay_signature: sig,
      name,
      phone,
      email: rawEmail,
      password,
    } = await req.json();

    if (!oid || !pid || !sig) return json({ error: "Missing payment fields" }, 400);

    const { data: mem } = await sb.from("gym_memberships")
      .select("*, gym_membership_plans(name,duration_days,price)")
      .eq("razorpay_order_id", oid).maybeSingle();
    if (!mem) return json({ error: "Membership order not found" }, 404);

    // Idempotent: already activated (customer retrying after closing the
    // tab, or a duplicate submit) — just hand back the existing membership.
    if (mem.status === "active") {
      return json({
        ok: true, memberCode: mem.member_code,
        startDate: mem.start_date, endDate: mem.end_date,
      });
    }

    const email = String(rawEmail ?? "").trim().toLowerCase();
    if (!email || !String(name ?? "").trim())
      return json({ error: "Missing name or email" }, 400);
    if (String(password ?? "").length < 8)
      return json({ error: "Password must be at least 8 characters" }, 400);

    const expected = await hmacHex(`${oid}|${pid}`, keySecret);
    if (!timingSafeEqual(expected, sig)) {
      try {
        await sb.from("audit_log").insert({
          event: "gold_payment_verify_fail",
          detail: { razorpay_order_id: oid, payment_id: pid },
        });
      } catch (_) { /* non-fatal */ }
      return json({ error: "Payment could not be verified" }, 400);
    }

    // Create (or reuse) the auth user for the customer app's Gold area.
    let authUserId: string;
    const { data: created, error: createErr } = await sb.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { gold_member: true, name },
    });
    if (createErr) {
      const { data: list } = await sb.auth.admin.listUsers();
      const existing = list?.users?.find(
        (u: any) => (u.email ?? "").toLowerCase() === email,
      );
      if (!existing) return json({ error: createErr.message }, 400);
      authUserId = existing.id;
      await sb.auth.admin.updateUserById(authUserId, { password });
    } else {
      authUserId = created.user.id;
    }
    await sb.from("profiles").upsert(
      { id: authUserId, email, role: "gold_member" },
      { onConflict: "id" },
    );

    const plan = (mem as any).gym_membership_plans;
    const duration = Number(plan?.duration_days ?? 30);
    const start = istDate(0);
    const end = new Date(new Date(start + "T00:00:00Z").getTime() +
      (duration - 1) * 86400_000).toISOString().slice(0, 10);

    let memberCode = mem.member_code as string | null;
    if (!memberCode) {
      const { data: code } = await sb.rpc("next_member_code");
      memberCode = String(code ?? `GLD-${String(mem.id).slice(0, 4).toUpperCase()}`);
    }

    const { error: upErr } = await sb.from("gym_memberships").update({
      status: "active",
      customer_name: String(name).trim(),
      phone: String(phone ?? ""),
      email,
      auth_user_id: authUserId,
      member_code: memberCode,
      start_date: start,
      end_date: end,
      razorpay_payment_id: pid,
      amount_paid: plan ? Number(plan.price) : null,
      updated_at: new Date().toISOString(),
    }).eq("id", mem.id);
    if (upErr) return json({ error: "Could not activate membership" }, 500);

    return json({ ok: true, memberCode, startDate: start, endDate: end });
  } catch (e) {
    console.error("gym-membership-activate error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
