import {
  assertAlmostEquals,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { haversineMeters } from "./geofence.ts";

Deno.test("distance from a point to itself is 0", () => {
  assertEquals(haversineMeters(13.34148, 77.119933, 13.34148, 77.119933), 0);
});

Deno.test("1 degree of latitude is ~111,195m on the sphere this formula assumes", () => {
  // Moving along a meridian (same longitude) traces an exact great-circle
  // arc, so this is independently computable: (1° in radians) * R, not just
  // "whatever the code currently outputs" — a real known-answer check.
  const expected = (Math.PI / 180) * 6371000; // ≈ 111194.93
  const actual = haversineMeters(0, 0, 1, 0);
  assertAlmostEquals(actual, expected, 0.01);
});

Deno.test("distance is symmetric (A→B equals B→A)", () => {
  const ab = haversineMeters(13.34148, 77.119933, 13.35, 77.13);
  const ba = haversineMeters(13.35, 77.13, 13.34148, 77.119933);
  assertEquals(ab, ba);
});

Deno.test("the actual COD center point is within its own 50m radius (delivery to the restaurant itself)", () => {
  const centerLat = 13.341439, centerLng = 77.119896;
  const distance = haversineMeters(centerLat, centerLng, centerLat, centerLng);
  assertEquals(distance <= 50, true);
});

Deno.test("a delivery point ~1.3km away is correctly outside a 50m COD radius", () => {
  // The exact pair used in the live geofence test earlier this session —
  // pins the "should reject" case with the real production config values.
  const centerLat = 13.341439, centerLng = 77.119896;
  const farLat = 13.35, farLng = 77.13;
  const distance = haversineMeters(centerLat, centerLng, farLat, farLng);
  assertEquals(distance > 50, true);
});
