-- One-time migration: makes the nightly WhatsApp meal-reminder send time
-- configurable from Admin → Subscriptions → Settings → WHATSAPP tab, instead
-- of fixed at 8 PM IST in the cron schedule.
--
-- Run once in the Supabase SQL Editor. Replace <CRON_SECRET> below with the
-- same value you used when you first set up cron.schedule (SUBSCRIPTION_SETUP.sql).

-- Default reminder time (IST) — matches the previous fixed 8 PM schedule.
-- The admin panel updates this row when the time is changed; never edit by hand
-- unless you want to override before the panel is used.
INSERT INTO public.app_config (key, value, description, updated_at)
VALUES (
  'meal_reminder_time',
  '{"hour": 20, "minute": 0}'::jsonb,
  'Nightly meal-reminder WhatsApp send time (IST)',
  now()
)
ON CONFLICT (key) DO NOTHING;

-- Tracks the last IST date a reminder was actually sent, so the more frequent
-- poll below only fires once per day. Edge-function-managed only — never
-- edited from the admin panel.
INSERT INTO public.app_config (key, value, description, updated_at)
VALUES (
  'meal_reminder_last_sent',
  '{"date": ""}'::jsonb,
  'Last IST date the nightly reminder was sent (internal)',
  now()
)
ON CONFLICT (key) DO NOTHING;

-- Reschedule from "fire once at a fixed UTC time" to "check every 5 minutes" —
-- the edge function itself now decides whether it's actually due, based on
-- meal_reminder_time / meal_reminder_last_sent above. Calling cron.schedule
-- again with the same job name updates the existing job in place (no
-- duplicate job is created).
SELECT cron.schedule(
  'send-daily-meal-whatsapp',
  '*/5 * * * *',
  $cron$
  SELECT net.http_post(
    url     := 'https://pahanghosyepfuwcfexg.supabase.co/functions/v1/send-daily-meal-whatsapp',
    headers := '{"Content-Type":"application/json","x-cron-secret":"<CRON_SECRET>"}'::jsonb,
    body    := '{"source":"pg_cron"}'::jsonb
  );
  $cron$
);
