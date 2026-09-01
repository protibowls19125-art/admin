-- One-time migration: per-item add-ons (name + price), replacing the
-- hardcoded "Extra Avocado / Quinoa Base / Extra Protein" list that used to
-- show on every product regardless of what it actually was. Empty by
-- default — the product page hides the ADD-ONS section entirely when a
-- menu item has none.
--
-- Run once in the Supabase SQL Editor.

ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS addons JSONB NOT NULL DEFAULT '[]'::jsonb;
