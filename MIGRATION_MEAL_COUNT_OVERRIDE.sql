-- One-time migration: lets a manager override how many meals a member gets
-- on a SPECIFIC day (e.g. bump from their usual 2 to 3), reviewed against
-- reply_text (the member's raw WhatsApp reply) from Today's Meal. NULL means
-- "use the plan's normal meals_per_day" — this only ever overrides a single
-- day, never the member's standing plan.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS meal_count INTEGER;

ALTER TABLE public.meal_confirmations
  DROP CONSTRAINT IF EXISTS meal_confirmations_meal_count_check;

ALTER TABLE public.meal_confirmations
  ADD CONSTRAINT meal_confirmations_meal_count_check
  CHECK (meal_count IS NULL OR meal_count >= 2);
