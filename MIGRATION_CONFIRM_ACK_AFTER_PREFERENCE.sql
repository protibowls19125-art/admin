-- One-time migration: lets whatsapp-webhook hold back confirm_ack ("your
-- meal is confirmed") until AFTER the member answers food_preference_confirm
-- (veg/non-veg), instead of sending it immediately on YES. Without this flag
-- the webhook can't tell "already sent the final ack today" apart from
-- "still waiting on the preference reply".
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS confirm_ack_sent BOOLEAN NOT NULL DEFAULT false;
