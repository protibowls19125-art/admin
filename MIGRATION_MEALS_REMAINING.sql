-- One-time migration: a real "meals remaining" balance on each subscription,
-- instead of the calendar-estimate (days-left × meals/day) the Members and
-- Survey Responses pages compute on the fly. Starts at the plan total
-- (duration_days × meals_per_day) and is decremented by whatsapp-webhook /
-- admin-confirm-meal whenever a day's meal actually gets confirmed — and
-- given back if a confirm is later reversed to a skip.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS meals_remaining INTEGER;

-- Backfill members already mid-plan: plan total minus meals already
-- confirmed so far, so the counter starts accurate rather than full.
UPDATE public.subscriptions s
SET meals_remaining = GREATEST(
  0,
  (p.duration_days * p.meals_per_day) - COALESCE((
    SELECT COUNT(*) FROM public.meal_confirmations mc
    WHERE mc.subscription_id = s.id AND mc.status IN
      ('confirmed', 'preparing', 'prepared', 'out_for_delivery', 'delivered')
  ), 0)
)
FROM public.subscription_plans p
WHERE s.plan_id = p.id
  AND s.status IN ('active', 'paused')
  AND s.meals_remaining IS NULL;

-- Atomic increment/decrement (avoids a read-modify-write race between
-- concurrent webhook deliveries) — never below zero.
CREATE OR REPLACE FUNCTION public.adjust_meals_remaining(sub_id uuid, delta int)
RETURNS integer
LANGUAGE sql
AS $$
  UPDATE public.subscriptions
  SET meals_remaining = GREATEST(0, COALESCE(meals_remaining, 0) + delta),
      updated_at = now()
  WHERE id = sub_id
  RETURNING meals_remaining;
$$;
