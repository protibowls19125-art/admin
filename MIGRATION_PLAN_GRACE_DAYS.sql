-- Per-plan grace period: how many days PAST end_date a member with unused
-- meals_remaining still gets the daily WhatsApp automation, before the
-- plan-completion sweep (send-daily-meal-whatsapp) hard-expires them and any
-- leftover meals are forfeited. Editable per plan from Admin → Subscriptions
-- → Plans, same as duration_days/meals_per_day.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS grace_days INTEGER NOT NULL DEFAULT 3;
