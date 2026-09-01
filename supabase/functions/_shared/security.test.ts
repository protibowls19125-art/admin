import { assertEquals, assertNotEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { hmacHex } from "./security.ts";

// Known-answer test — RFC 4231 HMAC-SHA256 test case 2 (key="key", data="The
// quick brown fox jumps over the lazy dog"), so this pins the implementation
// against a standard vector, not just "whatever the code currently outputs".
Deno.test("hmacHex matches the RFC 4231 known-answer test vector", async () => {
  const result = await hmacHex("The quick brown fox jumps over the lazy dog", "key");
  assertEquals(
    result,
    "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
  );
});

Deno.test("hmacHex is deterministic for the same message+secret", async () => {
  const a = await hmacHex("razorpay_order_id|payment_id", "secret");
  const b = await hmacHex("razorpay_order_id|payment_id", "secret");
  assertEquals(a, b);
});

Deno.test("hmacHex changes if the message changes (payment id tampering is detectable)", async () => {
  const original = await hmacHex("order_1|payment_1", "secret");
  const tampered = await hmacHex("order_1|payment_2", "secret");
  assertNotEquals(original, tampered);
});

Deno.test("hmacHex changes if the secret changes (a forged signature with the wrong secret fails)", async () => {
  const real = await hmacHex("order_1|payment_1", "real-secret");
  const forged = await hmacHex("order_1|payment_1", "guessed-secret");
  assertNotEquals(real, forged);
});

Deno.test("hmacHex output is always 64 lowercase hex characters (SHA-256)", async () => {
  const result = await hmacHex("anything", "anything");
  assertEquals(result.length, 64);
  assertEquals(/^[0-9a-f]{64}$/.test(result), true);
});
