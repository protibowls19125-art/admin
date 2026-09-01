-- One-time migration: makes the reply-by cutoff shown in the nightly
-- WhatsApp meal-reminder message ({{cutoff_time}}) admin-configurable from
-- Admin → Subscriptions → Settings → WHATSAPP SEND, instead of hardcoded as
-- "11:00 PM tonight" in send-daily-meal-whatsapp.
--
-- Run once in the Supabase SQL Editor.

-- Default cutoff (IST) — matches the previous hardcoded "11:00 PM".
-- The admin panel updates this row when the cutoff is changed; never edit by
-- hand unless you want to override before the panel is used.
INSERT INTO public.app_config (key, value, description, updated_at)
VALUES (
  'meal_reminder_cutoff_time',
  '{"hour": 23, "minute": 0}'::jsonb,
  'Reply-by deadline (IST) shown in the meal-reminder message',
  now()
)
ON CONFLICT (key) DO NOTHING;
