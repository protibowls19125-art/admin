import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  istDate,
  last10,
  loadTemplate,
  loadWhatsAppConfig,
  prettyDate,
  renderTemplate,
  sendWhatsAppText,
} from "../_shared/whatsapp.ts";
import { hmacHex, timingSafeEqual } from "../_shared/security.ts";
import { mealsRemainingDelta } from "../_shared/meals-balance.ts";
import { sendPush } from "../_shared/push.ts";

// Receives WhatsApp replies to the daily question (same-day cycle: 8am ask
// about today, 11am cutoff — see send-daily-meal-whatsapp).
//   GET  → Meta webhook verification (hub.challenge echo).
//   POST → member replies YES/NO → today's meal_confirmations row is
//          flipped to confirmed/skipped and an acknowledgement is sent back
//          (templates `confirm_ack` / `skip_ack`, editable in admin panel).
//
// Secrets:
//   WHATSAPP_VERIFY_TOKEN — set the same value in the Meta webhook config.
//   WHATSAPP_APP_SECRET   — required and enforced: requests without a valid
//                           X-Hub-Signature-256 are rejected with 401. Must
//                           match the Meta App's real App Secret exactly.

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: { "Content-Type": "application/json", "X-Content-Type-Options": "nosniff" },
  });

const YES_WORDS = ["yes", "y", "confirm", "confirmed", "ok", "okay", "haan", "ha", "yes please", "1"];
const NO_WORDS = ["no", "n", "skip", "cancel", "nahi", "not today", "2"];

// sendWhatsAppText's {ok,error} was previously discarded at every call site
// below — a failed ack was invisible anywhere. Logs to the same audit_log
// table the bad-signature/wa_status events already use (see MONITORING.sql),
// so failures are queryable instead of only living in unreachable function
// logs.
async function sendAndLogFailure(
  sb: any,
  cfg: { accessToken: string; phoneNumberId: string },
  to: string,
  text: string,
  context: string,
) {
  const r = await sendWhatsAppText(cfg, to, text);
  if (!r.ok) {
    try {
      await sb.from("audit_log").insert({
        event: "wa_send_failed",
        detail: { to, context, error: r.error },
      });
    } catch (_) { /* non-fatal */ }
  }
  return r;
}

// Push to subs managers when a member confirms via WhatsApp — best-effort,
// same non-fatal shape as sendAndLogFailure above: a push failure must never
// break the member-facing ack flow.
async function notifySubsManagerOfConfirmation(sb: any, memberName: string) {
  try {
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!serviceAccountJson) return;
    const { data: managers } = await sb.from("profiles").select("id")
      .in("role", ["admin", "developer", "sub_manager"]);
    const managerIds = (managers ?? []).map((p: any) => p.id);
    if (managerIds.length === 0) return;
    const { data: tokens } = await sb.from("device_tokens")
      .select("id, fcm_token").in("user_id", managerIds);
    if (!tokens || tokens.length === 0) return;
    await sendPush(
      sb, serviceAccountJson, tokens,
      "Meal confirmed",
      `${memberName || "A member"} confirmed today's meal via WhatsApp.`,
      "/subs",
    );
  } catch (e) {
    console.error("notifySubsManagerOfConfirmation failed:", e);
  }
}

serve(async (req: Request) => {
  // ── Meta verification handshake ────────────────────────────────────────────
  if (req.method === "GET") {
    const u = new URL(req.url);
    const mode = u.searchParams.get("hub.mode");
    const token = u.searchParams.get("hub.verify_token");
    const challenge = u.searchParams.get("hub.challenge") ?? "";
    const expected = Deno.env.get("WHATSAPP_VERIFY_TOKEN") ?? "";
    if (mode === "subscribe" && expected && token === expected) {
      return new Response(challenge, { status: 200 });
    }
    return new Response("Forbidden", { status: 403 });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Server not configured" }, 500);
    const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

    const raw = await req.text();

    // Fail closed: without a configured secret, there's no way to tell a
    // real Meta payload from anyone who found this URL and forged one
    // (e.g. faking a "yes" reply to silently drain a member's meal balance).
    // A misconfigured secret must break the feature loudly, not run unauthenticated.
    const appSecret = Deno.env.get("WHATSAPP_APP_SECRET") ?? "";
    if (!appSecret) {
      console.error("whatsapp-webhook: WHATSAPP_APP_SECRET is not configured");
      return json({ error: "Server not configured" }, 500);
    }
    const given = (req.headers.get("x-hub-signature-256") ?? "")
      .replace(/^sha256=/, "");
    const expected = await hmacHex(raw, appSecret);
    if (!timingSafeEqual(given, expected)) {
      try {
        await sb.from("audit_log").insert({
          event: "wa_webhook_bad_signature", detail: {},
        });
      } catch (_) { /* non-fatal */ }
      return json({ error: "Bad signature" }, 401);
    }

    const payload = JSON.parse(raw || "{}");
    const messages: any[] = [];
    const statuses: any[] = [];
    for (const entry of payload.entry ?? []) {
      for (const change of entry.changes ?? []) {
        for (const m of change.value?.messages ?? []) messages.push(m);
        for (const s of change.value?.statuses ?? []) statuses.push(s);
      }
    }
    // ponytail: temporary diagnostic — logs delivery status/errors so a
    // silent-drop send can be root-caused. Remove once WhatsApp send is
    // confirmed reliable.
    if (statuses.length > 0) {
      try {
        await sb.from("audit_log").insert(
          statuses.map((s) => ({ event: "wa_status", detail: s })),
        );
      } catch (_) { /* non-fatal */ }
    }
    // Always 200 for non-message events (statuses etc.) so Meta doesn't retry.
    if (messages.length === 0) return json({ ok: true });

    const cfg = await loadWhatsAppConfig(sb);
    const targetDate = istDate(0);

    const { data: cutoffCfg } = await sb.from("app_config")
      .select("value").eq("key", "meal_reminder_cutoff_time").maybeSingle();
    const cutoffHour = (cutoffCfg?.value as any)?.hour ?? 23;
    const cutoffMinute = (cutoffCfg?.value as any)?.minute ?? 0;
    
    const nowIst = new Date(Date.now() + 5.5 * 60 * 60_000);
    const isPastCutoff = nowIst.getUTCHours() > cutoffHour ||
        (nowIst.getUTCHours() === cutoffHour && nowIst.getUTCMinutes() >= cutoffMinute);

    for (const m of messages) {
      const from = String(m.from ?? ""); // international digits

      // Completion of the "today's meal" survey Flow — delivered as a
      // regular incoming message once the member taps Done on the terminal
      // screen. The DB was already updated screen-by-screen by
      // whatsapp-flow-endpoint; this just sends the member a confirmation.
      if (m.type === "interactive" && m.interactive?.type === "nfm_reply") {
        if (cfg) {
          let summary = "";
          try {
            const responseJson = JSON.parse(
              String(m.interactive.nfm_reply?.response_json ?? "{}"),
            );
            summary = String(responseJson?.summary ?? "");
          } catch (_) { /* malformed/empty payload — fall through to generic ack */ }
          
          if (isPastCutoff) {
             await sendAndLogFailure(sb, cfg, from, "Sorry, the cutoff time for today's meal has passed. Your meal has been automatically skipped.", "flow_reply_late");
          } else {
             await sendAndLogFailure(sb, cfg, from, summary
               ? `You're all set for today: ${summary} 🍽️`
               : "Got it — today's meal is marked as skipped. See you next time! 💚",
               "flow_reply_ack");
          }
        }
        continue;
      }

      // Text reply or interactive button reply.
      let text = "";
      if (m.type === "text") text = String(m.text?.body ?? "");
      else if (m.type === "button") text = String(m.button?.text ?? "");
      else if (m.type === "interactive") {
        text = String(m.interactive?.button_reply?.title ??
          m.interactive?.list_reply?.title ?? "");
      }
      if (!text.trim()) continue; // nothing to record (e.g. media-only message)
      const norm = text.trim().toLowerCase();
      let isYes = YES_WORDS.includes(norm);
      let isNo = !isYes && NO_WORDS.includes(norm);

      // Enforce the cutoff: if they reply YES or NO after the cutoff, force it to NO (skipped)
      if ((isYes || isNo) && isPastCutoff) {
        isYes = false;
        isNo = true;
      }

      // Match sender → active member by last-10-digit phone.
      const { data: subs } = await sb.from("subscriptions")
        .select("id,customer_name,phone,food_preference,subscription_plans(meals_per_day)")
        .eq("status", "active");
      const sub = (subs ?? []).find((s: any) => last10(s.phone) === last10(from));
      if (!sub) continue;

      // Today's row BEFORE this message, so a non-yes/no reply can be told
      // apart as "the veg/non-veg answer to food_preference_confirm" (sent
      // right after YES, confirm_ack still pending) vs. anything else.
      const { data: existingMeal } = await sb.from("meal_confirmations")
        .select("status,confirm_ack_sent")
        .eq("subscription_id", sub.id).eq("meal_date", targetDate).maybeSingle();
      const awaitingPrefReply = existingMeal?.status === "confirmed" &&
        !existingMeal.confirm_ack_sent;

      // Always record the member's raw reply — verbatim, whatever it says —
      // so Survey Responses shows it even when it doesn't parse as yes/no.
      // Status only flips for a recognized yes/no, and only while the row
      // is still in the member's hands (not already prepared/dispatched).
      const nowIso = new Date().toISOString();
      const statusFields = (isYes || isNo)
        ? { status: isYes ? "confirmed" : "skipped", confirmed_via: "whatsapp", confirmed_at: nowIso }
        : {};
      const { data: updated } = await sb.from("meal_confirmations")
        .update({
          reply_text: text.trim().slice(0, 500),
          ...statusFields,
          updated_at: nowIso,
        })
        .eq("subscription_id", sub.id)
        .eq("meal_date", targetDate)
        .in("status", ["awaiting", "confirmed", "skipped"])
        .select("id");
      // Did this message actually flip the row's status (vs. just recording
      // reply_text on one already past awaiting/confirmed/skipped)? Set below
      // whichever branch actually applies statusFields.
      let statusChanged = Boolean(updated && updated.length > 0);
      if (!updated || updated.length === 0) {
        // No row updated — either none exists yet (replied before the daily
        // job ran) or it exists but has already moved past awaiting/
        // confirmed/skipped (e.g. prepared/dispatched). INSERT would violate
        // the (subscription_id, meal_date) unique constraint in the second
        // case, so check first: an already-advanced row still gets the raw
        // reply_text recorded (for Survey Responses / a manager's manual
        // decision), just without touching its kitchen-pipeline status.
        const { data: existing } = await sb.from("meal_confirmations")
          .select("id").eq("subscription_id", sub.id)
          .eq("meal_date", targetDate).maybeSingle();
        if (existing) {
          await sb.from("meal_confirmations")
            .update({ reply_text: text.trim().slice(0, 500), updated_at: nowIso })
            .eq("id", existing.id);
        } else {
          await sb.from("meal_confirmations").insert({
            subscription_id: sub.id,
            meal_date: targetDate,
            reply_text: text.trim().slice(0, 500),
            ...statusFields,
          });
          statusChanged = isYes || isNo; // fresh row, statusFields applied
        }
      }

      // Adjust the meals-remaining balance for a genuine status flip — not
      // on a duplicate/retried yes (Meta redelivers webhooks) or a reply
      // that only landed on an already-advanced (prepared/dispatched) row.
      if (statusChanged) {
        const mealsPerDay =
          ((sub as any).subscription_plans?.meals_per_day as number) ?? 1;
        const wasConfirmed = existingMeal?.status === "confirmed";
        const delta = mealsRemainingDelta(isYes, isNo, wasConfirmed, mealsPerDay);
        if (delta !== 0) {
          await sb.rpc("adjust_meals_remaining", { sub_id: sub.id, delta });
        }
        if (isYes) {
          await notifySubsManagerOfConfirmation(sb, sub.customer_name);
        }
      }
      // The veg/non-veg reply to food_preference_confirm — updates the
      // member's standing preference (drives the KDS veg/non-veg counts) and
      // sends confirm_ack now: the LAST message in the sequence, after we
      // actually know what to cook, not immediately on YES.
      if (!isYes && !isNo && awaitingPrefReply) {
        const isVeg = ["veg", "vegetarian", "1"].includes(norm);
        const isNonVeg =
          ["non veg", "non-veg", "nonveg", "non vegetarian", "2"].includes(norm);
        if (isVeg || isNonVeg) {
          await sb.from("subscriptions")
            .update({ food_preference: isVeg ? "veg" : "non_veg" })
            .eq("id", sub.id);
        }
        await sb.from("meal_confirmations")
          .update({ confirm_ack_sent: true, updated_at: nowIso })
          .eq("subscription_id", sub.id).eq("meal_date", targetDate);
        if (cfg) {
          const tpl = await loadTemplate(sb, "confirm_ack");
          if (tpl) {
            await sendAndLogFailure(sb, cfg, from, renderTemplate(tpl, {
              name: sub.customer_name || "there",
              date: prettyDate(targetDate),
            }), "confirm_ack_after_preference");
          }
        }
        continue;
      }
      if (!isYes && !isNo) continue; // unrecognized — recorded, but nothing to acknowledge

      // Acknowledge (best-effort).
      if (cfg) {
        if (isNo) {
          const tpl = await loadTemplate(sb, "skip_ack");
          if (tpl) {
            await sendAndLogFailure(sb, cfg, from, renderTemplate(tpl, {
              name: sub.customer_name || "there",
              date: prettyDate(targetDate),
            }), "skip_ack");
          }
        } else {
          // isYes: confirm_ack no longer sent here — it now comes LAST,
          // after food_preference_confirm is asked and answered (see the
          // awaitingPrefReply branch above).
          const prefTpl = await loadTemplate(sb, "food_preference_confirm");
          if (prefTpl) {
            await sendAndLogFailure(sb, cfg, from, renderTemplate(prefTpl, {
              name: sub.customer_name || "there",
            }), "food_preference_confirm");
          }
        }
      }
    }

    return json({ ok: true });
  } catch (e) {
    console.error("whatsapp-webhook error:", e);
    // 200 anyway — Meta retries aggressively on non-2xx and we log server-side.
    return json({ ok: false });
  }
});
