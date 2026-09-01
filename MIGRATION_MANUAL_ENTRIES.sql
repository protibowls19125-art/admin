-- One-time migration: "Manual Entries" — offline/walk-in leads or payments a
-- manager wants on record WITHOUT creating a real member (no login, no
-- subscription row, no WhatsApp automation). Kept separate from
-- public.subscriptions so they never show up in member counts, the nightly
-- meal reminder, or the KDS.
--
-- Exported to the same Google Sheet as orders/meal confirmations (see
-- MIGRATION_ORDERS_SHEET_EXPORT.sql / MIGRATION_SUBSCRIPTION_MEALS_SHEET_EXPORT.sql),
-- routed to its own tab via export-manual-entries-to-sheets.
--
-- Run once in the Supabase SQL Editor. Requires SUBSCRIPTION_SETUP.sql
-- already applied (uses public.is_sub_manager()).

CREATE TABLE IF NOT EXISTS public.manual_subscription_entries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_name   TEXT NOT NULL,
  phone           TEXT DEFAULT '',
  plan_name       TEXT DEFAULT '',
  amount          NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  notes           TEXT DEFAULT '',
  added_by        TEXT DEFAULT '',   -- admin email, for a paper trail
  synced_to_sheet BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_manual_entries_unsynced
  ON public.manual_subscription_entries (created_at)
  WHERE synced_to_sheet = false;

ALTER TABLE public.manual_subscription_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "manual_entries_manager_all" ON public.manual_subscription_entries;
CREATE POLICY "manual_entries_manager_all" ON public.manual_subscription_entries
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- Nightly export (pg_cron → export-manual-entries-to-sheets edge function).
-- Runs at 00:05 IST = 18:35 UTC (previous day) — a few minutes after the
-- meal-confirmations export so they don't fight over the webhook.
-- pg_cron/pg_net + CRON_SECRET already set up by earlier migrations.
--
-- Replace <CRON_SECRET> below with the live value, then run:

-- SELECT cron.schedule(
--   'export-manual-entries-to-sheets',
--   '35 18 * * *',
--   $cron$
--   SELECT net.http_post(
--     url     := 'https://esiatypehvnyeemvnzbl.supabase.co/functions/v1/export-manual-entries-to-sheets',
--     headers := '{"Content-Type":"application/json","x-cron-secret":"<CRON_SECRET>"}'::jsonb,
--     body    := '{"source":"pg_cron"}'::jsonb
--   );
--   $cron$
-- );
