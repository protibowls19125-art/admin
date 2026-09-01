-- One-time migration: admin-editable badge list for menu_items.badge
-- (VEG / NON-VEG / PLANT-BASED...), replacing the hardcoded VEG/NON-VEG-only
-- chip pair in the admin menu item form. Same shape/pattern as the
-- subscription model's food_preferences table.
--
-- Keys match the literal values already stored in menu_items.badge ('VEG',
-- 'NON-VEG') so existing items don't need a data migration.
--
-- Run once in the Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.menu_badges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text NOT NULL UNIQUE,
  label text NOT NULL,
  color text NOT NULL DEFAULT 'blueGrey',
  sort_order integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.menu_badges ENABLE ROW LEVEL SECURITY;

-- Public (customer app) reads only active badges; admin/developer sees all
-- (so a just-disabled badge still shows correctly in the editor).
CREATE POLICY menu_badges_public_read ON public.menu_badges
  FOR SELECT USING (active = true OR is_admin());

-- Same write gate as menu_items itself, since badges are edited from the
-- same admin menu-item form.
CREATE POLICY menu_badges_admin_write ON public.menu_badges
  FOR ALL USING (is_admin());

INSERT INTO public.menu_badges (key, label, color, sort_order) VALUES
  ('VEG', 'VEG', 'green', 0),
  ('NON-VEG', 'NON-VEG', 'red', 1),
  ('PLANT-BASED', 'PLANT-BASED', 'teal', 2)
ON CONFLICT (key) DO NOTHING;
