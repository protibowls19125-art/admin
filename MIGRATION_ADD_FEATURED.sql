-- ─────────────────────────────────────────────────────────────────────────────
-- Featured Creation
-- Adds a `featured` flag to menu_items so the admin app can choose which dish
-- appears as the "Featured Creation" hero on the customer menu screen.
-- Run this once in the Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS featured boolean NOT NULL DEFAULT false;

-- Fast lookup of the (single) featured item for the customer app.
CREATE INDEX IF NOT EXISTS idx_menu_items_featured
  ON menu_items (featured)
  WHERE featured = true;

-- Note: the app enforces a single featured item — selecting one in the admin
-- clears the flag on any previously featured dish.
