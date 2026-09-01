import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// Pinned (not floating @2): esm.sh's build of supabase-js@2.112.2 —
// npm's "latest" as of this edit — 404s on its postgrest-js@2.112.2
// dependency (upstream esm.sh build gap, not a real missing package).
// 2.112.1 is the last version with a working denonext build.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.112.1";
import {
  istDate,
  loadTemplate,
  loadWhatsAppConfig,
  sendWhatsAppTemplate,
  toWaNumber,
} from "../_shared/whatsapp.ts";

// Manager-only member lifecycle. Requires a valid staff JWT whose profile
// role is admin or sub_manager — verified server-side on EVERY call.
//
// actions:
//   approve        { subscription_id, email, password }  → create login, activate
//   reject         { subscription_id, reason }
//   remove         { subscription_id }                    → cancel + ban login
//   add_manual     { plan_id, customer_name, phone, email, password,
//                    food_preference, health_goal, delivery_address,
//                    is_test }  → is_test: true excludes this member from
//                    every real aggregate stat and starts their plan today
//                    instead of tomorrow, for exercising the reminder cycle
//                    on demand (see subscriptions_page.dart "ADD TEST MEMBER")
//   reset_password { subscription_id, password }
//   edit_details   { subscription_id, customer_name, phone, food_preference,
//                    morning_preference, evening_preference, health_goal,
//                    health_notes, delivery_address }
//                    → only once the member has submitted onboarding details
//                    (status is no longer payment_received)

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
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    // ── AuthZ: caller must be an authenticated sub_manager or admin ─────────
    const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Not authorized" }, 401);
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "Not authorized" }, 401);
    const { data: profile } = await sb.from("profiles")
      .select("role,email").eq("id", userData.user.id).maybeSingle();
    if (!profile ||
        !["admin", "developer", "sub_manager"].includes(profile.role ?? ""))
      return json({ error: "Forbidden" }, 403);
    const actor = profile.email ?? userData.user.email ?? "manager";

    const body = await req.json();
    const action = String(body.action ?? "");
    const now = new Date().toISOString();

    // ── APPROVE: create the member's login and activate the plan ────────────
    if (action === "approve") {
      const subId = String(body.subscription_id ?? "");
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if (!subId || !email) return json({ error: "Missing fields" }, 400);
      // Basic email format check — prevents injection/malformed values.
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
        return json({ error: "Invalid email format" }, 400);
      if (password.length < 8)
        return json({ error: "Password must be at least 8 characters" }, 400);

      const { data: sub } = await sb.from("subscriptions")
        .select("*, subscription_plans(name,duration_days,meals_per_day)")
        .eq("id", subId).maybeSingle();
      if (!sub) return json({ error: "Subscription not found" }, 404);
      if (sub.status !== "pending_approval")
        return json({ error: `Cannot approve a ${sub.status} subscription` }, 409);

      // Create (or reuse) the auth user for the customer app member area.
      let authUserId: string;
      const { data: created, error: createErr } = await sb.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { member: true, name: sub.customer_name },
      });
      if (createErr) {
        // Already registered? Look it up and reuse (idempotent approvals).
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
        { id: authUserId, email, role: "member" },
        { onConflict: "id" },
      );

      const plan = (sub as any).subscription_plans;
      const duration = Number(plan?.duration_days ?? 30);
      const mealsPerDay = Number(plan?.meals_per_day ?? 1);
      const start = istDate(1); // meals begin tomorrow
      const end = new Date(new Date(start + "T00:00:00Z").getTime() +
        (duration - 1) * 86400_000).toISOString().slice(0, 10);

      let memberCode = sub.member_code as string | null;
      if (!memberCode) {
        const { data: code } = await sb.rpc("next_member_code");
        memberCode = String(code ?? `MP-${subId.slice(0, 4).toUpperCase()}`);
      }

      const { error: upErr } = await sb.from("subscriptions").update({
        status: "active",
        auth_user_id: authUserId,
        email,
        member_code: memberCode,
        start_date: start,
        end_date: end,
        meals_remaining: duration * mealsPerDay,
        approved_by: actor,
        approved_at: now,
        updated_at: now,
      }).eq("id", subId);
      if (upErr) return json({ error: "Could not activate subscription" }, 500);

      // Welcome message (best-effort — approval succeeds even if WA is not set up).
      let welcomeSent = false;
      const cfg = await loadWhatsAppConfig(sb);
      // Business-initiated (member hasn't messaged us yet), so this must be an
      // approved Meta template, not free text — see do_you_need_meal_today above.
      const tplActive = cfg ? (await loadTemplate(sb, "welcome_member")) !== null : false;
      if (cfg && tplActive && sub.phone) {
        const r = await sendWhatsAppTemplate(cfg, toWaNumber(sub.phone),
          "welcome_member", "en", [
            sub.customer_name || "there",
            memberCode ?? "",
            plan?.name ?? "meal",
          ]);
        welcomeSent = r.ok;
      }

      return json({
        ok: true, memberCode, startDate: start, endDate: end, welcomeSent,
      });
    }

    // ── REJECT ───────────────────────────────────────────────────────────────
    if (action === "reject") {
      const subId = String(body.subscription_id ?? "");
      if (!subId) return json({ error: "Missing subscription_id" }, 400);
      const { error } = await sb.from("subscriptions").update({
        status: "rejected",
        rejection_reason: String(body.reason ?? "").slice(0, 500),
        approved_by: actor,
        updated_at: now,
      }).eq("id", subId).eq("status", "pending_approval");
      if (error) return json({ error: "Could not reject" }, 500);
      return json({ ok: true });
    }

    // ── REMOVE: cancel membership + disable the login ───────────────────────
    if (action === "remove") {
      const subId = String(body.subscription_id ?? "");
      if (!subId) return json({ error: "Missing subscription_id" }, 400);
      const { data: sub } = await sb.from("subscriptions")
        .select("id,auth_user_id").eq("id", subId).maybeSingle();
      if (!sub) return json({ error: "Subscription not found" }, 404);

      await sb.from("subscriptions").update({
        status: "cancelled", updated_at: now,
      }).eq("id", subId);
      // Cancel any meals still in the pipeline.
      await sb.from("meal_confirmations")
        .update({ status: "missed", updated_at: now })
        .eq("subscription_id", subId)
        .gte("meal_date", istDate(0))
        .in("status", ["awaiting", "confirmed"]);
      if (sub.auth_user_id) {
        try {
          await sb.auth.admin.updateUserById(sub.auth_user_id, {
            ban_duration: "87600h", // ~10 years
          });
        } catch (_) { /* non-fatal */ }
      }
      return json({ ok: true });
    }

    // ── ADD MANUAL: manager onboards a member directly (offline payment) ────
    if (action === "add_manual") {
      const planId = String(body.plan_id ?? "");
      const name = String(body.customer_name ?? "").trim().slice(0, 120);
      const phone = String(body.phone ?? "").replace(/[^\d+]/g, "").slice(0, 15);
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if (!planId || !name || !email) return json({ error: "Missing fields" }, 400);
      // Basic email format check — prevents injection/malformed values.
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
        return json({ error: "Invalid email format" }, 400);
      if (password.length < 8)
        return json({ error: "Password must be at least 8 characters" }, 400);

      const { data: plan } = await sb.from("subscription_plans")
        .select("id,name,duration_days,meals_per_day,price")
        .eq("id", planId).maybeSingle();
      if (!plan) return json({ error: "Plan not found" }, 404);

      const { data: created, error: createErr } = await sb.auth.admin.createUser({
        email, password, email_confirm: true,
        user_metadata: { member: true, name },
      });
      if (createErr) return json({ error: createErr.message }, 400);
      await sb.from("profiles").upsert(
        { id: created.user.id, email, role: "member" }, { onConflict: "id" });

      const { data: code } = await sb.rpc("next_member_code");
      // A test member's plan starts TODAY, not tomorrow — the whole point is
      // testing the same-day reminder cycle immediately, not waiting for it.
      const isTest = body.is_test === true;
      const start = isTest ? istDate(0) : istDate(1);
      const end = new Date(new Date(start + "T00:00:00Z").getTime() +
        (Number(plan.duration_days) - 1) * 86400_000).toISOString().slice(0, 10);

      const { data: row, error: insErr } = await sb.from("subscriptions").insert({
        plan_id: plan.id,
        customer_name: name,
        phone,
        email,
        food_preference: String(body.food_preference ?? ""),
        health_goal: String(body.health_goal ?? ""),
        health_notes: String(body.health_notes ?? "").slice(0, 1000),
        delivery_address: body.delivery_address ?? {},
        status: "active",
        amount_paid: isTest ? 0 : Number(plan.price),
        is_test: isTest,
        auth_user_id: created.user.id,
        member_code: String(code ?? ""),
        start_date: start,
        end_date: end,
        meals_remaining:
          Number(plan.duration_days) * Number(plan.meals_per_day ?? 1),
        approved_by: actor,
        approved_at: now,
      }).select("id,member_code").single();
      if (insErr) return json({ error: "Could not create member" }, 500);
      return json({ ok: true, subscriptionId: row.id, memberCode: row.member_code });
    }

    // ── EDIT DETAILS: fix up what the member submitted, before/after approval ──
    if (action === "edit_details") {
      const subId = String(body.subscription_id ?? "");
      if (!subId) return json({ error: "Missing subscription_id" }, 400);
      const { data: sub } = await sb.from("subscriptions")
        .select("status").eq("id", subId).maybeSingle();
      if (!sub) return json({ error: "Subscription not found" }, 404);
      if (sub.status === "payment_received")
        return json({ error: "Member hasn't submitted their details yet" }, 409);

      const { error } = await sb.from("subscriptions").update({
        customer_name: String(body.customer_name ?? "").trim().slice(0, 120),
        phone: String(body.phone ?? "").replace(/[^\d+]/g, "").slice(0, 15),
        food_preference: String(body.food_preference ?? ""),
        morning_preference: String(body.morning_preference ?? ""),
        evening_preference: String(body.evening_preference ?? ""),
        health_goal: String(body.health_goal ?? ""),
        health_notes: String(body.health_notes ?? "").slice(0, 1000),
        delivery_address: body.delivery_address ?? {},
        updated_at: now,
      }).eq("id", subId);
      if (error) return json({ error: "Could not update member" }, 500);
      return json({ ok: true });
    }

    // ── RESET PASSWORD ───────────────────────────────────────────────────────
    if (action === "reset_password") {
      const subId = String(body.subscription_id ?? "");
      const password = String(body.password ?? "");
      if (password.length < 8)
        return json({ error: "Password must be at least 8 characters" }, 400);
      const { data: sub } = await sb.from("subscriptions")
        .select("auth_user_id").eq("id", subId).maybeSingle();
      if (!sub?.auth_user_id) return json({ error: "Member login not found" }, 404);
      const { error } = await sb.auth.admin.updateUserById(
        sub.auth_user_id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    console.error("admin-manage-member error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
