import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { istDate } from "../_shared/whatsapp.ts";

// Data endpoint for the "Today's meal" WhatsApp Flow (survey), same-day cycle.
// Screens: MEAL -> PREFERENCE -> (MIXED_TIME if mixed) -> SUCCESS, or
// MEAL(no) -> SKIP. Each screen's data is written to the DB as it's
// submitted, so a member closing mid-flow doesn't lose earlier answers.
//
// Implements Meta's Flow encryption protocol: the request body's AES key is
// RSA-OAEP(SHA-256)-encrypted with our public key; the payload is
// AES-128-GCM-encrypted with that key. The response is AES-128-GCM-encrypted
// with the SAME key but every byte of the IV flipped, base64-encoded, and
// returned as raw text (not JSON).
//
// Secrets: WHATSAPP_FLOW_PRIVATE_KEY — PEM, literal "\n" for newlines.

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/, "")
    .replace(/-----END [A-Z ]+-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToB64(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

async function getPrivateKey(): Promise<CryptoKey> {
  const pem = (Deno.env.get("WHATSAPP_FLOW_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
  const der = pemToDer(pem);
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSA-OAEP", hash: "SHA-256" },
    false,
    ["decrypt"],
  );
}

interface DecryptedRequest {
  version: string;
  action: string;
  screen?: string;
  data?: Record<string, unknown>;
  flow_token?: string;
}

async function decryptRequest(body: {
  encrypted_flow_data: string;
  encrypted_aes_key: string;
  initial_vector: string;
}): Promise<{ request: DecryptedRequest; aesKey: CryptoKey; iv: Uint8Array }> {
  const privateKey = await getPrivateKey();
  const aesKeyRaw = await crypto.subtle.decrypt(
    { name: "RSA-OAEP" },
    privateKey,
    b64ToBytes(body.encrypted_aes_key),
  );
  const aesKey = await crypto.subtle.importKey(
    "raw",
    aesKeyRaw,
    { name: "AES-GCM" },
    false,
    ["decrypt", "encrypt"],
  );
  const iv = b64ToBytes(body.initial_vector);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    aesKey,
    b64ToBytes(body.encrypted_flow_data),
  );
  const request = JSON.parse(new TextDecoder().decode(plaintext)) as DecryptedRequest;
  return { request, aesKey, iv };
}

async function encryptResponse(
  data: Record<string, unknown>,
  aesKey: CryptoKey,
  requestIv: Uint8Array,
): Promise<string> {
  // Response IV = request IV with every byte flipped — required by Meta so
  // the same underlying random IV is never reused verbatim in both directions.
  const flippedIv = requestIv.map((b) => b ^ 0xff);
  const plaintext = new TextEncoder().encode(JSON.stringify(data));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: flippedIv },
    aesKey,
    plaintext,
  );
  return bytesToB64(new Uint8Array(ciphertext));
}

function summaryText(pref: string, morning: string, evening: string): string {
  if (pref === "mixed") {
    return `MIXED — Morning: ${morning === "veg" ? "VEG" : "NON-VEG"}, Evening: ${evening === "veg" ? "VEG" : "NON-VEG"}`;
  }
  return pref === "veg" ? "VEG (whole day)" : "NON-VEG (whole day)";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return new Response("Server not configured", { status: 500 });
  const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

  let decrypted: Awaited<ReturnType<typeof decryptRequest>>;
  try {
    const body = await req.json();
    decrypted = await decryptRequest(body);
  } catch (e) {
    console.error("whatsapp-flow-endpoint decrypt error:", e);
    // 421 tells WhatsApp our key may be stale, prompting a re-fetch.
    return new Response("Decryption failed", { status: 421 });
  }

  const { request, aesKey, iv } = decrypted;

  try {
    if (request.action === "ping") {
      const enc = await encryptResponse({ data: { status: "active" } }, aesKey, iv);
      return new Response(enc, { headers: { "Content-Type": "text/plain" } });
    }

    const subscriptionId = request.flow_token ?? "";
    const targetDate = istDate(0); // same-day cycle — see send-daily-meal-whatsapp

    if (request.action === "INIT") {
      const enc = await encryptResponse({ screen: "MEAL", data: {} }, aesKey, iv);
      return new Response(enc, { headers: { "Content-Type": "text/plain" } });
    }

    if (request.action === "data_exchange") {
      const screen = request.screen ?? "";
      const data = request.data ?? {};

      if (screen === "MEAL") {
        const wantMeal = data.want_meal === "yes";
        if (!wantMeal) {
          const { data: updated } = await sb.from("meal_confirmations")
            .update({ status: "skipped", confirmed_via: "whatsapp_flow",
              confirmed_at: new Date().toISOString(), updated_at: new Date().toISOString() })
            .eq("subscription_id", subscriptionId).eq("meal_date", targetDate)
            .select("id");
          if (!updated || updated.length === 0) {
            await sb.from("meal_confirmations").insert({
              subscription_id: subscriptionId, meal_date: targetDate, status: "skipped",
              confirmed_via: "whatsapp_flow", confirmed_at: new Date().toISOString(),
            });
          }
          const enc = await encryptResponse({ screen: "SKIP", data: {} }, aesKey, iv);
          return new Response(enc, { headers: { "Content-Type": "text/plain" } });
        }

        const { data: updated } = await sb.from("meal_confirmations")
          .update({ status: "confirmed", confirmed_via: "whatsapp_flow",
            confirmed_at: new Date().toISOString(), updated_at: new Date().toISOString() })
          .eq("subscription_id", subscriptionId).eq("meal_date", targetDate)
          .select("id");
        if (!updated || updated.length === 0) {
          await sb.from("meal_confirmations").insert({
            subscription_id: subscriptionId, meal_date: targetDate, status: "confirmed",
            confirmed_via: "whatsapp_flow", confirmed_at: new Date().toISOString(),
          });
        }
        const enc = await encryptResponse({ screen: "PREFERENCE", data: {} }, aesKey, iv);
        return new Response(enc, { headers: { "Content-Type": "text/plain" } });
      }

      if (screen === "PREFERENCE") {
        const pref = String(data.preference ?? "");
        if (pref === "mixed") {
          await sb.from("subscriptions").update({ food_preference: "mixed" })
            .eq("id", subscriptionId);
          const enc = await encryptResponse({ screen: "MIXED_TIME", data: {} }, aesKey, iv);
          return new Response(enc, { headers: { "Content-Type": "text/plain" } });
        }
        await sb.from("subscriptions").update({
          food_preference: pref, morning_preference: "", evening_preference: "",
        }).eq("id", subscriptionId);
        const enc = await encryptResponse(
          { screen: "SUCCESS", data: { summary: summaryText(pref, "", "") } }, aesKey, iv);
        return new Response(enc, { headers: { "Content-Type": "text/plain" } });
      }

      if (screen === "MIXED_TIME") {
        const morning = String(data.morning ?? "veg");
        const evening = String(data.evening ?? "veg");
        await sb.from("subscriptions").update({
          food_preference: "mixed", morning_preference: morning, evening_preference: evening,
        }).eq("id", subscriptionId);
        const enc = await encryptResponse(
          { screen: "SUCCESS", data: { summary: summaryText("mixed", morning, evening) } },
          aesKey, iv);
        return new Response(enc, { headers: { "Content-Type": "text/plain" } });
      }
    }

    // Unrecognized action/screen — end the flow gracefully rather than error.
    const enc = await encryptResponse({ screen: "SUCCESS", data: { summary: "" } }, aesKey, iv);
    return new Response(enc, { headers: { "Content-Type": "text/plain" } });
  } catch (e) {
    console.error("whatsapp-flow-endpoint error:", e);
    return new Response("Internal error", { status: 500 });
  }
});
