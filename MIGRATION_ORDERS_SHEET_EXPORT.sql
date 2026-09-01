-- =============================================================================
-- Daily order export to Google Sheets + Supabase storage pruning.
--
-- synced_to_sheet tracks which orders have already been appended to the
-- Google Sheet. export-orders-to-sheets (edge function) only ever deletes a
-- row from `orders` after it's confirmed synced_to_sheet = true, so a failed
-- Sheets API call never causes data loss — the row just stays and retries
-- next run.
-- =============================================================================

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS synced_to_sheet boolean NOT NULL DEFAULT false;

-- Sweeps the not-yet-synced backlog fast; small table so a partial index is
-- plenty (most rows will be true and never touched by this index).
CREATE INDEX IF NOT EXISTS idx_orders_unsynced
  ON public.orders (created_at)
  WHERE synced_to_sheet = false;
