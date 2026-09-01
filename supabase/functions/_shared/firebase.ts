// Turns a Firebase service account (env FIREBASE_SERVICE_ACCOUNT_JSON) into a
// short-lived OAuth2 access token for the FCM HTTP v1 API. No firebase-admin
// SDK — that's Node-only, not available in the Deno edge runtime — so this
// hand-rolls the standard "signed JWT → Google token endpoint" service
// account flow using Web Crypto (available in Deno).

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

export function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

// Cached across warm invocations of the same edge function instance — a
// fresh access token is only fetched once the cached one is near expiry.
let cachedToken: { value: string; expiresAt: number } | null = null;

export async function getFcmAccessToken(
  serviceAccountJson: string,
): Promise<{ token: string; projectId: string }> {
  const sa: ServiceAccount = JSON.parse(serviceAccountJson);

  if (cachedToken && cachedToken.expiresAt > Date.now() + 30_000) {
    return { token: cachedToken.value, projectId: sa.project_id };
  }

  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claim))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error("FCM token exchange failed: " + JSON.stringify(data));

  cachedToken = {
    value: data.access_token,
    expiresAt: Date.now() + (data.expires_in ?? 3600) * 1000,
  };
  return { token: cachedToken.value, projectId: sa.project_id };
}
