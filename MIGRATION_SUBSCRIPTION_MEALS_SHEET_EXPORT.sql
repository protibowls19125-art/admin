-- One-time migration: daily export of subscription meal confirmations
-- (plan, yes/no response, dish sent, meals remaining) to a Google Sheet —
-- same pattern as MIGRATION_ORDERS_SHEET_EXPORT.sql / export-orders-to-sheets,
-- but for meal_confirmations instead of orders, and with NO pruning: this
-- data keeps feeding Survey Responses / Today's Meal / KDS in the app, so
-- rows are never deleted, only marked synced.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS synced_to_sheet boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_meal_confirmations_unsynced
  ON public.meal_confirmations (meal_date)
  WHERE synced_to_sheet = false;

-- Nightly automation (pg_cron → export-subscription-meals-to-sheets edge
-- function). Runs at 00:00 IST = 18:30 UTC (previous day), so it exports the
-- day that just closed. pg_cron/pg_net must already be enabled (they are, as
-- of the meal-reminder automation) and CRON_SECRET already set.
--
-- Replace <CRON_SECRET> below with the live value, then run:

-- SELECT cron.schedule(
--   'export-subscription-meals-to-sheets',
--   '30 18 * * *',
--   $cron$
--   SELECT net.http_post(
--     url     := 'https://esiatypehvnyeemvnzbl.supabase.co/functions/v1/export-subscription-meals-to-sheets',
--     headers := '{"Content-Type":"application/json","x-cron-secret":"<CRON_SECRET>"}'::jsonb,
--     body    := '{"source":"pg_cron"}'::jsonb
--   );
--   $cron$
-- );
