import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  formatTime12h,
  last10,
  renderTemplate,
  toWaNumber,
} from "./whatsapp.ts";

// ── renderTemplate ──────────────────────────────────────────────────────

Deno.test("renderTemplate fills in a known placeholder", () => {
  assertEquals(
    renderTemplate("Hi {{name}}!", { name: "Aishwarya" }),
    "Hi Aishwarya!",
  );
});

Deno.test("renderTemplate fills multiple placeholders", () => {
  assertEquals(
    renderTemplate("{{name}}, your meal for {{date}} is confirmed", {
      name: "Aishwarya",
      date: "Tue, 15 Jul",
    }),
    "Aishwarya, your meal for Tue, 15 Jul is confirmed",
  );
});

Deno.test("renderTemplate removes unknown placeholders rather than leaking {{...}} literally", () => {
  assertEquals(renderTemplate("Hi {{name}}, code {{secret}}", { name: "A" }), "Hi A, code ");
});

Deno.test("renderTemplate tolerates whitespace inside braces", () => {
  assertEquals(renderTemplate("Hi {{ name }}", { name: "A" }), "Hi A");
});

// ── toWaNumber ──────────────────────────────────────────────────────────

Deno.test("toWaNumber prefixes a bare 10-digit Indian number with 91", () => {
  assertEquals(toWaNumber("9876543210"), "919876543210");
});

Deno.test("toWaNumber leaves an already-prefixed number alone", () => {
  assertEquals(toWaNumber("919876543210"), "919876543210");
});

Deno.test("toWaNumber strips formatting characters before checking length", () => {
  assertEquals(toWaNumber("+91 98765-43210"), "919876543210");
});

// ── last10 ──────────────────────────────────────────────────────────────

Deno.test("last10 matches a stored number to an incoming sender regardless of country-code formatting", () => {
  assertEquals(last10("+91 98765 43210"), last10("919876543210"));
  assertEquals(last10("9876543210"), "9876543210");
});

// ── formatTime12h ───────────────────────────────────────────────────────

Deno.test("formatTime12h formats midnight, noon, and an admin-configured cutoff correctly", () => {
  assertEquals(formatTime12h(0, 0), "12:00 AM");
  assertEquals(formatTime12h(12, 0), "12:00 PM");
  assertEquals(formatTime12h(8, 0), "8:00 AM"); // the actual send time
  assertEquals(formatTime12h(11, 0), "11:00 AM"); // the actual cutoff time
  assertEquals(formatTime12h(23, 5), "11:05 PM");
});
