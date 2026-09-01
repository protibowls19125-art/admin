import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { mealsRemainingDelta } from "./meals-balance.ts";

// admin-confirm-meal's usage (2-state: isNo is always !isYes).
Deno.test("admin path: yes on an unconfirmed meal claims a meal", () => {
  assertEquals(mealsRemainingDelta(true, false, false, 2), -2);
});
Deno.test("admin path: yes on an already-confirmed meal is a no-op (no double charge)", () => {
  assertEquals(mealsRemainingDelta(true, false, true, 2), 0);
});
Deno.test("admin path: no on a confirmed meal returns it", () => {
  assertEquals(mealsRemainingDelta(false, true, true, 2), 2);
});
Deno.test("admin path: no on an unconfirmed meal is a no-op", () => {
  assertEquals(mealsRemainingDelta(false, true, false, 2), 0);
});

// whatsapp-webhook's usage (3-state: a reply can be neither yes nor no).
Deno.test("webhook path: yes claims a meal", () => {
  assertEquals(mealsRemainingDelta(true, false, false, 1), -1);
});
Deno.test("webhook path: no on a confirmed meal returns it", () => {
  assertEquals(mealsRemainingDelta(false, true, true, 1), 1);
});
Deno.test(
  "webhook path: an ambiguous reply (neither yes nor no) never moves the balance, even on a confirmed meal",
  () => {
    // This is the exact bug caught during refactoring: deriving isNo from
    // !isYes would wrongly treat this as a "no" and refund the meal.
    assertEquals(mealsRemainingDelta(false, false, true, 1), 0);
  },
);
Deno.test(
  "webhook path: the veg/non-veg confirmation reply (isYes=false, isNo=false) never triggers a refund",
  () => {
    assertEquals(mealsRemainingDelta(false, false, true, 2), 0);
  },
);

Deno.test("respects a whole-day plan's meals-per-day, not just 1", () => {
  assertEquals(mealsRemainingDelta(true, false, false, 2), -2);
  assertEquals(mealsRemainingDelta(false, true, true, 3), 3);
});
