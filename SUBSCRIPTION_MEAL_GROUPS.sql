-- =============================================================================
-- Multi-dish daily menu + member groups + per-member meal assignment.
-- Run AFTER SUBSCRIPTION_MEALS.sql in the Supabase SQL Editor.
--
--   meal_schedule   : was ONE dish per (date, preference) — now MANY, i.e. the
--                     day's available options per preference.
--   member_groups   : named, reusable, preference-homogeneous member cohorts,
--                     so a manager can assign a dish to many members at once.
--   subscriptions.group_id     : which group (if any) a member belongs to.
--   meal_confirmations.meal_id : the RESOLVED dish for that member/day — set
--                     explicitly by an individual or group assign action,
--                     not re-derived live from meal_schedule at read time.
-- =============================================================================

-- ── 1. meal_schedule: allow multiple dishes per (date, preference) ──────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint
             WHERE conname = 'meal_schedule_meal_date_food_preference_key') THEN
    ALTER TABLE public.meal_schedule
      DROP CONSTRAINT meal_schedule_meal_date_food_preference_key;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'meal_schedule_date_pref_meal_key') THEN
    ALTER TABLE public.meal_schedule
      ADD CONSTRAINT meal_schedule_date_pref_meal_key
      UNIQUE (meal_date, food_preference, meal_id);
  END IF;
END $$;

-- ── 2. member_groups: named cohorts a dish can be bulk-assigned to ──────────
CREATE TABLE IF NOT EXISTS public.member_groups (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL,
  food_preference TEXT NOT NULL
                  CHECK (food_preference IN ('veg','non_veg','eggetarian','vegan')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.member_groups ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='member_groups'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.member_groups;', p.policyname);
  END LOOP;
END $$;

-- Internal management concept — staff read, manager write (not public).
CREATE POLICY "member_groups_staff_read" ON public.member_groups
  FOR SELECT TO authenticated USING (public.is_sub_staff());
CREATE POLICY "member_groups_manager_write" ON public.member_groups
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- ── 3. subscriptions.group_id ────────────────────────────────────────────────
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES public.member_groups(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_subscriptions_group ON public.subscriptions(group_id);
-- Covered by the existing "subs_manager_write" policy (FOR ALL, is_sub_manager()) — no new RLS.

-- ── 4. meal_confirmations.meal_id — the resolved per-member dish ────────────
ALTER TABLE public.meal_confirmations
  ADD COLUMN IF NOT EXISTS meal_id UUID REFERENCES public.subscription_meals(id) ON DELETE SET NULL;
-- Covered by existing policies: is_sub_manager() is a subset of is_sub_staff(),
-- so a manager's upsert already satisfies "meals_manager_insert" (INSERT) and
-- "meals_staff_update" (UPDATE) — no new RLS needed.
