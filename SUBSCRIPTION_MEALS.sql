-- =============================================================================
-- SUBSCRIPTION MEALS — the meal catalog + daily menu for the subscription
-- programme. SEPARATE from the restaurant's menu_items: the subscription
-- kitchen plans its own dishes, while both share the single customer website.
-- Run AFTER SUBSCRIPTION_SETUP.sql in the Supabase SQL Editor.
--
--   subscription_meals : the dish library (admin/manager curated)
--   meal_schedule      : which dish is served on which date, per preference
-- =============================================================================

-- ── 1. Meal library ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.subscription_meals (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  description     TEXT DEFAULT '',
  image_url       TEXT DEFAULT '',
  -- Which member preference this dish suits. 'all' fits every preference.
  food_preference TEXT NOT NULL DEFAULT 'all'
                  CHECK (food_preference IN ('veg','non_veg','eggetarian','vegan','all')),
  kcal            INTEGER DEFAULT 0,
  protein         NUMERIC(6,1) DEFAULT 0,
  carbs           NUMERIC(6,1) DEFAULT 0,
  fat             NUMERIC(6,1) DEFAULT 0,
  serving_size    TEXT DEFAULT '',
  active          BOOLEAN NOT NULL DEFAULT true,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 2. Daily menu: one dish per preference per date ─────────────────────────
CREATE TABLE IF NOT EXISTS public.meal_schedule (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meal_date       DATE NOT NULL,
  food_preference TEXT NOT NULL
                  CHECK (food_preference IN ('veg','non_veg','eggetarian','vegan')),
  meal_id         UUID NOT NULL REFERENCES public.subscription_meals(id) ON DELETE CASCADE,
  notes           TEXT DEFAULT '',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (meal_date, food_preference)
);
CREATE INDEX IF NOT EXISTS idx_meal_schedule_date ON public.meal_schedule(meal_date);

-- ── 3. RLS ───────────────────────────────────────────────────────────────────
ALTER TABLE public.subscription_meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meal_schedule      ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname, tablename FROM pg_policies
           WHERE schemaname='public'
             AND tablename IN ('subscription_meals','meal_schedule')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', p.policyname, p.tablename);
  END LOOP;
END $$;

-- The single customer website shows meal details → public read of ACTIVE
-- dishes and the schedule; only managers (or full admin) write.
CREATE POLICY "sub_meals_public_read" ON public.subscription_meals
  FOR SELECT USING (active = true OR public.is_sub_manager());
CREATE POLICY "sub_meals_manager_write" ON public.subscription_meals
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

CREATE POLICY "meal_schedule_public_read" ON public.meal_schedule
  FOR SELECT USING (true);
CREATE POLICY "meal_schedule_manager_write" ON public.meal_schedule
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- ── 4. Storage: let the sub_manager upload meal photos to menu-images ───────
-- (Existing policies are admin-only; policies are OR'd, so these ADD access.)
DROP POLICY IF EXISTS "menu_images_submgr_write"  ON storage.objects;
DROP POLICY IF EXISTS "menu_images_submgr_update" ON storage.objects;
DROP POLICY IF EXISTS "menu_images_submgr_delete" ON storage.objects;
CREATE POLICY "menu_images_submgr_write" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'menu-images' AND public.is_sub_manager());
CREATE POLICY "menu_images_submgr_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'menu-images' AND public.is_sub_manager());
CREATE POLICY "menu_images_submgr_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'menu-images' AND public.is_sub_manager());

-- ── 5. Starter dishes (first run only) ───────────────────────────────────────
INSERT INTO public.subscription_meals
  (name, description, food_preference, kcal, protein, carbs, fat, serving_size, sort_order)
SELECT * FROM (VALUES
  ('Grilled Paneer Power Bowl',
   'Char-grilled paneer, quinoa, roasted seasonal veggies and mint yogurt.',
   'veg', 520, 32.0, 45.0, 18.0, '400 g', 1),
  ('Herb Chicken & Brown Rice',
   'Pan-seared herb chicken breast, brown rice, sautéed greens.',
   'non_veg', 560, 42.0, 48.0, 14.0, '420 g', 2),
  ('Masala Egg Protein Plate',
   'Spiced whole eggs, millet pilaf and cucumber raita.',
   'eggetarian', 480, 28.0, 40.0, 16.0, '380 g', 3),
  ('Tofu Buddha Bowl',
   'Crispy tofu, chickpeas, brown rice and tahini drizzle.',
   'vegan', 500, 26.0, 52.0, 15.0, '400 g', 4)
) AS v(name, description, food_preference, kcal, protein, carbs, fat, serving_size, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.subscription_meals);
