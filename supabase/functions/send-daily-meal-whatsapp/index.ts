import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  formatTime12h,
  istDate,
  loadTemplate,
  loadWhatsAppConfig,
  prettyDate,
  renderTemplate,
  sendWhatsAppTemplate,
  sendWhatsAppText,
  toWaNumber,
} from "../_shared/whatsapp.ts";

// The DAILY automation, same-day cycle. For every active member it:
//   1. creates today's meal_confirmations row (status 'awaiting'),
//   2. sends the "do you want today's meal?" WhatsApp question
//      (template `do_you_need_meal_today`, editable in the admin panel).
// Reply-by cutoff (Admin → Subscriptions → WHATSAPP SEND) is later the SAME
// day as send — e.g. 8am send / 11am cutoff — not the next morning.
//
// Callable by:
//   • pg_cron          → header  x-cron-secret: <CRON_SECRET env>
//   • the admin panel  → Authorization: Bearer <manager JWT>  ("Send now" button)
//
// If WhatsApp credentials are not configured yet, the rows are STILL created
// so members can confirm inside the app — the job reports configured:false.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
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

    // ── AuthZ: cron secret OR a manager/admin JWT ────────────────────────────
    const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
    const givenSecret = req.headers.get("x-cron-secret") ?? "";
    let authorized = cronSecret.length > 0 && givenSecret === cronSecret;
    if (!authorized) {
      const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
      if (jwt) {
        const { data: userData } = await sb.auth.getUser(jwt);
        if (userData?.user) {
          const { data: profile } = await sb.from("profiles")
            .select("role").eq("id", userData.user.id).maybeSingle();
          authorized = ["admin", "developer", "sub_manager"].includes(profile?.role ?? "");
        }
      }
    }
    if (!authorized) return json({ error: "Not authorized" }, 401);

    // Manual trigger can target specific members instead of everyone active.
    let manualSubscriptionIds: string[] | null = null;
    try {
      const body = await req.json();
      if (Array.isArray(body?.subscription_ids) && body.subscription_ids.length > 0) {
        manualSubscriptionIds = body.subscription_ids as string[];
      }
    } catch (_) { /* no/invalid body — send to everyone, as before */ }

    // The meal being asked about — same calendar day as send (8am ask about
    // today, 11am cutoff same day), not the next day.
    const targetDate = istDate(0);
    const todayIst = targetDate;
    // Reply-by deadline shown in the message ({{cutoff_time}}) — set from
    // Admin → Subscriptions → WHATSAPP SEND, not hardcoded.
    const { data: cutoffCfg } = await sb.from("app_config")
      .select("value").eq("key", "meal_reminder_cutoff_time").maybeSingle();
    const cutoffHour = (cutoffCfg?.value as any)?.hour ?? 23;
    const cutoffMinute = (cutoffCfg?.value as any)?.minute ?? 0;
    const cutoff = `${formatTime12h(cutoffHour, cutoffMinute)} today`;

    // Which Meta template to actually send — admin-editable so a manager can
    // switch to whichever template is currently APPROVED without a code
    // deploy (do_you_need_meal_today is PENDING as of writing). Separate from
    // the whatsapp_templates "active" toggle below, which just turns the
    // reminder feature on/off.
    const { data: tplNameCfg } = await sb.from("app_config")
      .select("value").eq("key", "meal_reminder_template_name").maybeSingle();
    const templateName =
      (tplNameCfg?.value as any)?.name || "do_you_need_meal_today";

    // Cron polls every 5 minutes now (was: fire once at a fixed UTC time) so
    // the send time can be changed from the admin panel without redeploying.
    // Only cron-triggered calls are gated by it — a manual "Send now" from
    // the panel always sends immediately.
    const isCronTrigger = cronSecret.length > 0 && givenSecret === cronSecret;
    if (isCronTrigger) {
      // ── Auto-confirm sweep: no reply by the auto-confirm time = YES ─────
      // At a manager-configured IST time (default 11:00 AM), every 'awaiting'
      // meal_confirmations row for today is promoted to 'confirmed' — members
      // who forgot to reply still get their meal. Runs BEFORE the cutoff
      // sweep below (which catches anything left 'awaiting' after this and
      // marks it 'skipped' — a safety net for the rare case auto-confirm is
      // disabled or hasn't run yet).
      const { data: autoConfirmCfg } = await sb.from("app_config")
        .select("value").eq("key", "meal_auto_confirm_time").maybeSingle();
      const acEnabled = (autoConfirmCfg?.value as any)?.enabled !== false;
      const acHour = (autoConfirmCfg?.value as any)?.hour ?? 11;
      const acMinute = (autoConfirmCfg?.value as any)?.minute ?? 0;
      if (acEnabled) {
        const nowIstForAc = new Date(Date.now() + 5.5 * 60 * 60_000);
        const acDueNow = nowIstForAc.getUTCHours() > acHour ||
          (nowIstForAc.getUTCHours() === acHour &&
            nowIstForAc.getUTCMinutes() >= acMinute);
        const { data: acRunCfg } = await sb.from("app_config")
          .select("value").eq("key", "meal_auto_confirm_last_run").maybeSingle();
        const acLastRun = (acRunCfg?.value as any)?.date ?? "";
        if (acDueNow && acLastRun !== todayIst) {
          await sb.from("app_config").upsert({
            key: "meal_auto_confirm_last_run",
            value: { date: todayIst },
            description:
              "Last IST date unanswered meal_confirmations were auto-confirmed to YES (internal)",
            updated_at: new Date().toISOString(),
          }, { onConflict: "key" });
          const { count } = await sb.from("meal_confirmations")
            .update({
              status: "confirmed",
              reply_text: "auto-confirmed",
              updated_at: new Date().toISOString(),
            })
            .eq("meal_date", targetDate)
            .eq("status", "awaiting");
          console.log(`Auto-confirmed ${count ?? 0} unanswered meals for ${targetDate}`);
        }
      }

      // ── Cutoff auto-resolve: no reply by the cutoff = counted as NO ─────
      // Runs on every poll independent of the send-gating below — even on a
      // day the reminder never actually sent (e.g. template still pending),
      // members who never answered are finalized as skipped by the cutoff
      // instead of sitting "awaiting" forever. Same status a typed/tapped
      // NO reply sets (whatsapp-webhook) — shows up as NO in Survey Responses.
      //
      // Matches meal_date <= today (not === today) — today's row is the
      // normal target (same-day cutoff, no midnight crossed since send), and
      // <= also mops up any older awaiting row a missed poll left behind.
      const nowIstForCutoff = new Date(Date.now() + 5.5 * 60 * 60_000);
      const cutoffDueNow = nowIstForCutoff.getUTCHours() > cutoffHour ||
        (nowIstForCutoff.getUTCHours() === cutoffHour &&
          nowIstForCutoff.getUTCMinutes() >= cutoffMinute);
      const { data: cutoffRunCfg } = await sb.from("app_config")
        .select("value").eq("key", "meal_reminder_cutoff_last_run").maybeSingle();
      const cutoffLastRun = (cutoffRunCfg?.value as any)?.date ?? "";
      if (cutoffDueNow && cutoffLastRun !== todayIst) {
        await sb.from("app_config").upsert({
          key: "meal_reminder_cutoff_last_run",
          value: { date: todayIst },
          description:
            "Last IST date unanswered meal_confirmations were auto-resolved to NO (internal)",
          updated_at: new Date().toISOString(),
        }, { onConflict: "key" });
        await sb.from("meal_confirmations")
          .update({ status: "skipped" })
          .lte("meal_date", targetDate)
          .eq("status", "awaiting");
      }

      // ── Plan-completion sweep: close the plan out once it's truly done ──
      // Runs on every poll, same as the cutoff resolve above. Flipping status
      // to 'expired' IS the auto-remove-from-automation step — every query in
      // this file (and the admin Members list) filters on status='active', so
      // an expired row just stops being selected anywhere, no separate flag
      // needed.
      //
      // "Done" is either: meals_remaining hit 0 (nothing left to use), or the
      // plan's end_date plus its (admin-editable, per-plan) grace_days has
      // passed — a member who skipped days and banked unused meals still
      // gets grace_days extra days of automation to use them (see the
      // eligibility filter below), but forfeits anything left after that.
      // grace_days lives on the joined subscription_plans row, so this can't
      // be expressed as a single PostgREST filter — fetch active candidates
      // and decide in JS instead (cheap at this app's membership scale).
      const { data: activeCandidates } = await sb.from("subscriptions")
        .select("id,customer_name,phone,end_date,meals_remaining,subscription_plans(name,grace_days)")
        .eq("status", "active");
      const todayMs = new Date(todayIst + "T00:00:00").getTime();
      const toExpire = (activeCandidates ?? []).filter((sub: any) => {
        const mealsDone = sub.meals_remaining !== null && sub.meals_remaining <= 0;
        if (mealsDone) return true;
        if (!sub.end_date) return false;
        const graceDays = sub.subscription_plans?.grace_days ?? 3;
        const daysPastEnd =
          (todayMs - new Date(sub.end_date + "T00:00:00").getTime()) / 86_400_000;
        return daysPastEnd > graceDays;
      });
      let justExpired: any[] | null = null;
      if (toExpire.length > 0) {
        const { data } = await sb.from("subscriptions")
          .update({ status: "expired", updated_at: new Date().toISOString() })
          .in("id", toExpire.map((s: any) => s.id))
          .select("id,customer_name,phone,subscription_plans(name)");
        justExpired = data;
      }
      if (justExpired && justExpired.length > 0) {
        const expiryCfg = await loadWhatsAppConfig(sb);
        const expiryTpl = expiryCfg ? await loadTemplate(sb, "plan_completed") : null;
        if (expiryCfg && expiryTpl) {
          for (const sub of justExpired) {
            if (!sub.phone) continue;
            const plan = (sub as any).subscription_plans;
            const r = await sendWhatsAppText(
              expiryCfg,
              toWaNumber(sub.phone),
              renderTemplate(expiryTpl, {
                name: sub.customer_name || "there",
                plan: plan?.name ?? "meal plan",
              }),
            );
            if (!r.ok) {
              console.error(`plan_completed alert failed for ${sub.id}:`, r.error);
            }
          }
        }
      }
    }
    // Which members the AUTOMATED (cron) run should cover — "all" active
    // members (default) or an admin-picked subset. A manual send with
    // explicit subscription_ids always overrides this regardless of trigger.
    let autoSubscriptionIds: string[] | null = null;
    if (isCronTrigger) {
      const { data: timeCfg } = await sb.from("app_config")
        .select("value").eq("key", "meal_reminder_time").maybeSingle();
      const hour = (timeCfg?.value as any)?.hour ?? 20;
      const minute = (timeCfg?.value as any)?.minute ?? 0;
      const nowIst = new Date(Date.now() + 5.5 * 60 * 60_000);
      const dueNow = nowIst.getUTCHours() > hour ||
        (nowIst.getUTCHours() === hour && nowIst.getUTCMinutes() >= minute);

      const { data: sentCfg } = await sb.from("app_config")
        .select("value").eq("key", "meal_reminder_last_sent").maybeSingle();
      const lastSent = (sentCfg?.value as any)?.date ?? "";

      if (!dueNow || lastSent === todayIst) {
        return json({
          ok: true,
          skipped: true,
          reason: !dueNow ? "not due yet" : "already sent today",
        });
      }

      // ── Off-days: skip automation on admin-configured days of the week ──
      // 0=Sunday, 1=Monday, ..., 6=Saturday (JS Date.getDay() convention).
      // Manual sends from the admin panel bypass this check entirely.
      const { data: offDaysCfg } = await sb.from("app_config")
        .select("value").eq("key", "meal_reminder_off_days").maybeSingle();
      const offDays: number[] = (offDaysCfg?.value as any)?.days ?? [];
      if (offDays.length > 0) {
        // IST day-of-week for the target date (today).
        // A direct new Date(targetDate).getDay() uses the edge function's
        // local timezone (UTC), which would evaluate to the day BEFORE if
        // targetDate is early in the morning.
        const nowIst = new Date(Date.now() + 5.5 * 60 * 60_000);
        const todayDow = nowIst.getUTCDay();
        if (offDays.includes(todayDow)) {
          // Mark as "sent" so the poll doesn't retry later today.
          await sb.from("app_config").upsert({
            key: "meal_reminder_last_sent",
            value: { date: todayIst },
            description: "Last IST date the nightly reminder was sent (internal)",
            updated_at: new Date().toISOString(),
          }, { onConflict: "key" });
          const dayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
          return json({
            ok: true,
            skipped: true,
            reason: `off-day (${dayNames[todayDow]})`,
          });
        }
      }

      const { data: membersCfg } = await sb.from("app_config")
        .select("value").eq("key", "meal_reminder_members").maybeSingle();
      const mcfg = (membersCfg?.value as any) ?? {};
      if (mcfg.mode === "selected" && Array.isArray(mcfg.subscription_ids)) {
        autoSubscriptionIds = mcfg.subscription_ids as string[];
      }
    }

    // Mark today as sent before the loop, so an overlapping poll (or a
    // manual trigger later the same day) can't fire a second round.
    // ponytail: not a hard lock — a poll landing in the same few-hundred-ms
    // window as this write could still slip through. Fine at a 5-min cadence
    // for a single nightly job; add a DB-level lock if double-sends show up.
    await sb.from("app_config").upsert({
      key: "meal_reminder_last_sent",
      value: { date: todayIst },
      description: "Last IST date the nightly reminder was sent (internal)",
      updated_at: new Date().toISOString(),
    }, { onConflict: "key" });

    // Active members whose plan covers today — either genuinely within
    // start_date..end_date, or past end_date but still inside that plan's
    // grace_days with unused meals_remaining (see the plan-completion sweep
    // above for the matching hard-expiry). grace_days lives on the joined
    // plan row, so eligibility is decided in JS rather than a single
    // PostgREST filter — narrowed to a specific list when the manual send
    // picked members, or the automation is configured to cover only a subset.
    const targetIds = manualSubscriptionIds ?? autoSubscriptionIds;
    let subsQuery = sb.from("subscriptions")
      .select("id,customer_name,phone,member_code,food_preference,end_date,meals_remaining, subscription_plans(name,meals_per_day,grace_days)")
      .eq("status", "active")
      .lte("start_date", targetDate);
    if (targetIds) subsQuery = subsQuery.in("id", targetIds);
    const { data: candidateSubs, error: subErr } = await subsQuery;
    if (subErr) return json({ error: "Could not load members" }, 500);
    const targetMs = new Date(targetDate + "T00:00:00").getTime();
    const subs = (candidateSubs ?? []).filter((sub: any) => {
      if (!sub.end_date) return false; // matches the old .gte(end_date) behavior: NULL never matched
      if (sub.end_date >= targetDate) return true;
      const graceDays = sub.subscription_plans?.grace_days ?? 3;
      const daysPastEnd =
        (targetMs - new Date(sub.end_date + "T00:00:00").getTime()) / 86_400_000;
      return daysPastEnd <= graceDays && (sub.meals_remaining ?? 0) > 0;
    });

    let created = 0, sent = 0, failed = 0, skippedNoPhone = 0;
    let lastError: string | undefined;
    const cfg = await loadWhatsAppConfig(sb);
    // The admin's "do_you_need_meal_today" active toggle still gates whether this
    // fires — but its message_text no longer matters. This is sent as an
    // approved Meta message TEMPLATE with YES/NO quick-reply buttons (not
    // free text), since it's a business-initiated message and the member
    // may not have messaged us in the last 24 hours — free text would be
    // silently rejected in that case. Editing the wording means submitting
    // a new template version to Meta for approval, not editing the
    // template-text field in the admin panel. A YES tap is handled by
    // whatsapp-webhook exactly like a typed "yes" reply, which also fires
    // the veg/non-veg/mixed follow-up (food_preference_confirm).
    const tplEnabled = cfg
      ? (await loadTemplate(sb, "do_you_need_meal_today")) !== null
      : false;

    for (const sub of subs ?? []) {
      // 1. Ensure today's confirmation row exists (idempotent).
      const { error: insErr } = await sb.from("meal_confirmations")
        .insert({ subscription_id: sub.id, meal_date: targetDate });
      if (!insErr) created++;
      // (duplicate key on re-run is fine — row already exists)

      // 2. Ask on WhatsApp — params fill {{1}}..{{4}} in whichever template
      // is configured above (name, plan, date, cutoff_time, in that order —
      // must match the order that template was submitted to Meta with).
      if (cfg && tplEnabled) {
        if (!sub.phone) {
          skippedNoPhone++;
          continue;
        }
        const plan = (sub as any).subscription_plans;
        // food_preference_confirm only has {{1}}=name — a stopgap fallback
        // while the real meal-question templates are pending, so it needs
        // fewer params than the other two (name, plan, date, cutoff) or Meta
        // rejects the send on a parameter-count mismatch.
        const bodyParams = templateName === "food_preference_confirm"
          ? [sub.customer_name || "there"]
          : [
            sub.customer_name || "there",
            plan?.name ?? "meal plan",
            prettyDate(targetDate),
            cutoff,
          ];
        const r = await sendWhatsAppTemplate(
          cfg,
          toWaNumber(sub.phone),
          templateName,
          "en",
          bodyParams,
        );
        if (r.ok) {
          sent++;
        } else {
          failed++;
          lastError = r.error;
          console.error(`WhatsApp send failed for ${sub.id} (${sub.phone}):`, r.error);
        }
      }
    }

    return json({
      ok: true,
      mealDate: targetDate,
      members: (subs ?? []).length,
      rowsCreated: created,
      sent,
      failed,
      skippedNoPhone,
      configured: !!cfg,
      lastError,
    });
  } catch (e) {
    console.error("send-daily-meal-whatsapp error:", e);
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
