-- Per-item toggle: whether the product page shows customization
-- (spice level, standard includes, add-ons). Defaults to true (customizable).
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS customizable BOOLEAN DEFAULT true;
