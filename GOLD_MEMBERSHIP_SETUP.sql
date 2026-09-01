-- =============================================================================
-- GOLD MEMBERSHIP — gym-model-only paid membership: discount + free delivery
-- on regular gym orders. Independent of the subscription/Elite model (own
-- tables, own role, own RLS) — mirrors that system's shape where useful, but
-- with no manual-approval step (there's nothing for a manager to review; a
-- membership is a discount flag, not a meal-planning commitment).
--
-- Run this once in the Supabase SQL Editor, in order. Self-contained: it
-- (re-)defines is_gym_manager() and the profiles.role CHECK constraint from
-- scratch rather than assuming they already exist, since earlier ad-hoc SQL
-- for those was applied directly in the SQL editor and never committed here.
-- =============================================================================

-- ── 0. Foundation: is_gym_manager() + profiles.role CHECK constraint ────────
-- (Re-)defined idempotently — safe to run even if these already exist.
CREATE OR REPLACE FUNCTION public.is_gym_manager()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin','gym_manager')
  );
$$;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IS NULL OR role IN (
    'admin', 'gym_manager', 'sub_manager',
    'gym_chef', 'gym_delivery', 'subs_chef', 'subs_delivery',
    'member', 'user', 'gold_member'
  ));

-- ── 1. Plans (multiple tiers — admin-editable, mirrors subscription_plans) ──
CREATE TABLE IF NOT EXISTS public.gym_membership_plans (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name             TEXT NOT NULL,
  tagline          TEXT DEFAULT '',
  description      TEXT DEFAULT '',
  price            NUMERIC(10,2) NOT NULL CHECK (price >= 0),
  compare_at_price NUMERIC(10,2) NOT NULL DEFAULT 0,
  duration_days    INTEGER NOT NULL CHECK (duration_days > 0),
  -- % off every gym order while this membership is active. Gold-specific —
  -- subscription_plans has no equivalent, since Elite IS the product rather
  -- than a discount on something else.
  discount_percent NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (discount_percent BETWEEN 0 AND 100),
  features         JSONB NOT NULL DEFAULT '[]'::jsonb,
  badge            TEXT DEFAULT '',
  active           BOOLEAN NOT NULL DEFAULT true,
  sort_order       INTEGER NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 2. Memberships (one row per purchase) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gym_memberships (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id             UUID REFERENCES public.gym_membership_plans(id),
  customer_name       TEXT DEFAULT '',
  phone               TEXT DEFAULT '',
  email               TEXT DEFAULT '',
  status              TEXT NOT NULL DEFAULT 'awaiting_payment'
                       CHECK (status IN ('awaiting_payment','active','cancelled')),
  start_date          DATE,
  end_date            DATE,
  razorpay_order_id   TEXT,
  razorpay_payment_id TEXT,
  amount_paid         NUMERIC(10,2),
  auth_user_id        UUID,  -- auth.users id once login is created
  member_code         TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_gym_memberships_status  ON public.gym_memberships(status);
CREATE INDEX IF NOT EXISTS idx_gym_memberships_phone   ON public.gym_memberships(phone);
CREATE INDEX IF NOT EXISTS idx_gym_memberships_auth    ON public.gym_memberships(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_gym_memberships_rzp     ON public.gym_memberships(razorpay_order_id);

-- ── 3. RLS ───────────────────────────────────────────────────────────────────
ALTER TABLE public.gym_membership_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_memberships      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "gym_plans_public_read"  ON public.gym_membership_plans;
DROP POLICY IF EXISTS "gym_plans_manager_write" ON public.gym_membership_plans;
CREATE POLICY "gym_plans_public_read" ON public.gym_membership_plans
  FOR SELECT USING (active = true OR public.is_gym_manager());
CREATE POLICY "gym_plans_manager_write" ON public.gym_membership_plans
  FOR ALL TO authenticated
  USING (public.is_gym_manager()) WITH CHECK (public.is_gym_manager());

-- No anon access on memberships — all writes flow through edge functions
-- (service role). Members read their own row; gym managers read/write all.
DROP POLICY IF EXISTS "gym_memberships_member_read"  ON public.gym_memberships;
DROP POLICY IF EXISTS "gym_memberships_manager_write" ON public.gym_memberships;
CREATE POLICY "gym_memberships_member_read" ON public.gym_memberships
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR public.is_gym_manager());
CREATE POLICY "gym_memberships_manager_write" ON public.gym_memberships
  FOR ALL TO authenticated
  USING (public.is_gym_manager()) WITH CHECK (public.is_gym_manager());

-- ── 4. Seed one starter plan so the admin/customer pages aren't empty ───────
INSERT INTO public.gym_membership_plans (name, tagline, price, compare_at_price, duration_days, discount_percent, badge, sort_order)
SELECT 'Gold Monthly', 'Eat at the gym for less, every time', 499, 699, 30, 10, 'MOST POPULAR', 1
WHERE NOT EXISTS (SELECT 1 FROM public.gym_membership_plans);
