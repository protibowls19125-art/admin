-- One-time migration for two additions to the nightly meal-reminder flow:
--
-- 1. meal_reminder_template_name — which Meta template name is actually sent.
--    do_you_need_meal_today is PENDING approval as of writing; this lets a
--    manager switch to whichever template IS approved, from Admin →
--    Subscriptions → Settings → WHATSAPP SEND, without a code deploy.
--
-- 2. meal_reminder_cutoff_last_run — internal bookkeeping (like
--    meal_reminder_last_sent) so the cutoff auto-resolve-to-NO logic in
--    send-daily-meal-whatsapp only runs once per IST day.
--
-- Run once in the Supabase SQL Editor.

INSERT INTO public.app_config (key, value, description, updated_at)
VALUES (
  'meal_reminder_template_name',
  '{"name": "do_you_need_meal_today"}'::jsonb,
  'Meta template name sent for the nightly meal reminder',
  now()
)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.app_config (key, value, description, updated_at)
VALUES (
  'meal_reminder_cutoff_last_run',
  '{"date": ""}'::jsonb,
  'Last IST date unanswered meal_confirmations were auto-resolved to NO (internal)',
  now()
)
ON CONFLICT (key) DO NOTHING;
