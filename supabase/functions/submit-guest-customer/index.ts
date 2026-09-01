import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Creates a guest_customers row for a not-yet-logged-in customer. RLS locks
// that table to admins only (service_role bypasses RLS), so this write has
// to happen server-side — the anon client can no longer insert directly.

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

    const body = await req.json();
    const name = String(body.name ?? "").trim().slice(0, 120);
    const phone = String(body.phone ?? "").trim().slice(0, 20);
    const gender = String(body.gender ?? "").trim().slice(0, 20) || null;
    const preference = String(body.preference ?? "").trim().slice(0, 20) || null;
    if (!name || !phone) return json({ error: "Missing customer info" }, 400);
    // Phone: digits, +, spaces, hyphens only — no script/HTML injection.
    if (!/^[\d+\s\-()]{7,20}$/.test(phone))
      return json({ error: "Invalid phone number format" }, 400);

    const { data, error } = await sb.from("guest_customers")
      .insert({ name, phone, gender, preference, is_info_complete: true })
      .select("id")
      .single();
    if (error) return json({ error: "Could not save customer info" }, 500);

    return json({ id: data.id });
  } catch (e) {
    console.error("submit-guest-customer error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
