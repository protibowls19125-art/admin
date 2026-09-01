// Shared HMAC-SHA256 signing — used to verify Razorpay's payment/webhook
// signatures and Meta's X-Hub-Signature-256 on the WhatsApp webhook. Was
// duplicated byte-for-byte across 5 edge functions; consolidated here so
// there's one implementation to test and no risk of the copies drifting.

export async function hmacHex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Constant-time string comparison — prevents timing attacks on HMAC
 * signature verification. A naive `===` leaks how many leading bytes
 * match through response-time differences; this XOR-then-reduce approach
 * takes the same time regardless of where (or whether) the strings diverge.
 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

