import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Admin-only staff lifecycle (profiles.role = admin/gym_manager/sub_manager/
// gym_chef/gym_delivery/subs_chef/subs_delivery). Requires a valid JWT whose
// profile role is 'admin' — verified server-side on EVERY call. Anything
// needing the auth admin API (create login, ban, change password) has to go
// through here; role-only changes on an existing account are done directly
// from the client (RLS already restricts profiles writes to admins).
//
// actions:
//   invite          { email, password, role }              → create login + profile
//   revoke          { profile_id }                          → ban login + clear role
//   reactivate      { profile_id, role }                    → unban + set role
//   reset_password  { profile_id, password }
//   rename          { profile_id, email }                   → change login email
//   delete          { profile_id }                          → permanently remove login + profile

const STAFF_ROLES = [
  "admin", "developer", "gym_manager", "sub_manager",
  "gym_chef", "gym_delivery", "subs_chef", "subs_delivery",
];

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

    // ── AuthZ: caller must be an authenticated admin ────────────────────────
    const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Not authorized" }, 401);
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "Not authorized" }, 401);
    const { data: caller } = await sb.from("profiles")
      .select("role").eq("id", userData.user.id).maybeSingle();
    if (!["admin", "developer"].includes(caller?.role ?? ""))
      return json({ error: "Forbidden" }, 403);
    const callerId = userData.user.id;

    const body = await req.json();
    const action = String(body.action ?? "");

    // ── INVITE: create the staff member's login + profile ──────────────────
    if (action === "invite") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      const role = String(body.role ?? "");
      if (!email || !STAFF_ROLES.includes(role))
        return json({ error: "Missing or invalid fields" }, 400);
      // Basic email format check — prevents injection/malformed values.
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
        return json({ error: "Invalid email format" }, 400);
      if (password.length < 8)
        return json({ error: "Password must be at least 8 characters" }, 400);

      const { data: created, error: createErr } = await sb.auth.admin.createUser({
        email, password, email_confirm: true,
      });
      if (createErr) return json({ error: createErr.message }, 400);

      const { error: upErr } = await sb.from("profiles").upsert(
        { id: created.user.id, email, role }, { onConflict: "id" },
      );
      if (upErr) return json({ error: "Could not save profile" }, 500);
      return json({ ok: true });
    }

    // ── REVOKE: ban the login and clear the role ────────────────────────────
    if (action === "revoke") {
      const profileId = String(body.profile_id ?? "");
      if (!profileId) return json({ error: "Missing profile_id" }, 400);
      if (profileId === callerId)
        return json({ error: "You cannot revoke your own access" }, 400);

      const { error } = await sb.auth.admin.updateUserById(profileId, {
        ban_duration: "87600h", // ~10 years
      });
      if (error) return json({ error: error.message }, 400);
      await sb.from("profiles").update({ role: null }).eq("id", profileId);
      return json({ ok: true });
    }

    // ── REACTIVATE: unban the login and restore a role ──────────────────────
    if (action === "reactivate") {
      const profileId = String(body.profile_id ?? "");
      const role = String(body.role ?? "");
      if (!profileId || !STAFF_ROLES.includes(role))
        return json({ error: "Missing or invalid fields" }, 400);

      const { error } = await sb.auth.admin.updateUserById(profileId, {
        ban_duration: "none",
      });
      if (error) return json({ error: error.message }, 400);
      await sb.from("profiles").update({ role }).eq("id", profileId);
      return json({ ok: true });
    }

    // ── RESET PASSWORD ───────────────────────────────────────────────────────
    if (action === "reset_password") {
      const profileId = String(body.profile_id ?? "");
      const password = String(body.password ?? "");
      if (password.length < 8)
        return json({ error: "Password must be at least 8 characters" }, 400);
      const { error } = await sb.auth.admin.updateUserById(profileId, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    // ── RENAME: change the login email (auth + profile, kept in sync) ───────
    if (action === "rename") {
      const profileId = String(body.profile_id ?? "");
      const email = String(body.email ?? "").trim().toLowerCase();
      if (!profileId || !email)
        return json({ error: "Missing profile_id or email" }, 400);

      const { error } = await sb.auth.admin.updateUserById(profileId, {
        email, email_confirm: true,
      });
      if (error) return json({ error: error.message }, 400);
      const { error: upErr } = await sb.from("profiles")
        .update({ email }).eq("id", profileId);
      if (upErr) return json({ error: "Could not update profile email" }, 500);
      return json({ ok: true });
    }

    // ── DELETE: permanently remove the login and the profile row ────────────
    if (action === "delete") {
      const profileId = String(body.profile_id ?? "");
      if (!profileId) return json({ error: "Missing profile_id" }, 400);
      if (profileId === callerId)
        return json({ error: "You cannot delete your own access" }, 400);

      const { error } = await sb.auth.admin.deleteUser(profileId);
      // "not found" is fine here — the login may already be gone while the
      // profile row lingered; still proceed to clean up the profile.
      if (error && !/not.*found/i.test(error.message))
        return json({ error: error.message }, 400);
      await sb.from("profiles").delete().eq("id", profileId);
      return json({ ok: true });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    console.error("admin-manage-staff error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
