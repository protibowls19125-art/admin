import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.112.1";

// Manager-only Gold member password reset. Requires a valid staff JWT whose
// profile role is admin, developer, or gym_manager — same set is_gym_manager()
// grants for gym_memberships RLS, verified server-side on every call (the
// service-role auth.admin call below bypasses RLS entirely, so this check is
// the only gate).
//
// POST { membership_id, password }

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

    // ── AuthZ: caller must be admin, developer, or gym_manager ───────────────
    const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Not authorized" }, 401);
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user) return json({ error: "Not authorized" }, 401);
    const { data: profile } = await sb.from("profiles")
      .select("role").eq("id", userData.user.id).maybeSingle();
    if (!profile ||
        !["admin", "developer", "gym_manager"].includes(profile.role ?? ""))
      return json({ error: "Forbidden" }, 403);

    const body = await req.json();
    const membershipId = String(body.membership_id ?? "");
    const password = String(body.password ?? "");
    if (!membershipId) return json({ error: "Missing membership_id" }, 400);
    if (password.length < 8)
      return json({ error: "Password must be at least 8 characters" }, 400);

    const { data: mem } = await sb.from("gym_memberships")
      .select("auth_user_id").eq("id", membershipId).maybeSingle();
    if (!mem?.auth_user_id) return json({ error: "Member login not found" }, 404);

    const { error } = await sb.auth.admin.updateUserById(
      mem.auth_user_id, { password });
    if (error) return json({ error: error.message }, 400);

    return json({ ok: true });
  } catch (e) {
    console.error("gym-membership-reset-password error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
