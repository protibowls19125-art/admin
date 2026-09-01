-- One-time migration: stores the member's raw WhatsApp reply text on their
-- meal_confirmations row, so Admin → Subscriptions → Survey Responses can
-- show exactly what they typed — not just the yes/no the webhook managed to
-- parse out of it. Previously any reply that wasn't an exact match for the
-- YES/NO word list was silently dropped and never stored anywhere.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS reply_text TEXT;
