-- =============================================================================
-- Fix: menu_items is missing the nutrition / availability columns the app uses,
-- so saving a menu item with nutrition values fails ("column ... does not exist").
-- Adds every column the MenuItem model expects, idempotently. SQL-only.
-- =============================================================================

ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS kcal            INTEGER       DEFAULT 0,
  ADD COLUMN IF NOT EXISTS serving_size    TEXT          DEFAULT '',
  ADD COLUMN IF NOT EXISTS protein         NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS carbs           NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fat             NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fiber           NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS daily_limit     INTEGER,
  ADD COLUMN IF NOT EXISTS orders_today    INTEGER       DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_reset_date TEXT          DEFAULT '',
  ADD COLUMN IF NOT EXISTS badge           TEXT,
  ADD COLUMN IF NOT EXISTS featured        BOOLEAN       DEFAULT false,
  ADD COLUMN IF NOT EXISTS tags            JSONB         DEFAULT '[]'::jsonb;
