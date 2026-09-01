import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { base64url } from "./firebase.ts";

Deno.test("base64url strips padding and uses URL-safe chars", () => {
  // "any carnal pleas" is the classic base64 test string whose standard
  // encoding contains both '+' and '/' — the exact chars base64url must swap.
  const encoded = base64url("any carnal pleas");
  assertEquals(encoded, "YW55IGNhcm5hbCBwbGVhcw");
  assertEquals(encoded.includes("+"), false);
  assertEquals(encoded.includes("/"), false);
  assertEquals(encoded.includes("="), false);
});

Deno.test("JSON header round-trips through base64url the way a JWT segment must", () => {
  const header = JSON.stringify({ alg: "RS256", typ: "JWT" });
  const encoded = base64url(header);
  const decoded = atob(encoded.replace(/-/g, "+").replace(/_/g, "/"));
  assertEquals(decoded, header);
});
