import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Lets a guest customer poll the status of orders they placed, by the order
// UUIDs they already hold (unguessable). Returns ONLY id/status/order_number —
// no PII — so locking `orders` down to admins doesn't break order tracking.

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

    const UUID_RE =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const body = await req.json();
    // Keep only well-formed UUIDs so malformed input can't error the query.
    const ids = (Array.isArray(body.ids) ? body.ids : [])
      .map((x: unknown) => String(x).trim())
      .filter((x: string) => UUID_RE.test(x))
      .slice(0, 50);
    if (ids.length === 0) return json({ orders: [] });

    const { data, error } = await sb.from("orders")
      .select("id,status,order_number")
      .in("id", ids);
    if (error) return json({ error: "Lookup failed" }, 500);

    return json({ orders: data ?? [] });
  } catch (e) {
    console.error("get-order-status error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
