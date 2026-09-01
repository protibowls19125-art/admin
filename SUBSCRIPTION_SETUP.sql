-- =============================================================================
-- SUBSCRIPTION MODEL — meal-plan subscriptions with home delivery.
-- Run AFTER SECURITY_HARDENING.sql + ROLES.sql in the Supabase SQL Editor.
--
-- Flow:
--   customer picks plan → pays (Razorpay, server-verified) → fills details
--   → status 'pending_approval' → sub-manager approves & creates login
--   → nightly WhatsApp asks "meal tomorrow?" → confirmed meals appear on the
--     Subscription KDS → chef prepares → manager assigns delivery agent.
--
-- Roles (profiles.role):
--   admin        → everything
--   sub_manager  → subscription section only (separate credentials)
--   chef         → KDS + subscription KDS
--   member       → the customer app member area (their own data only)
-- =============================================================================

-- ── 1. Role helpers ──────────────────────────────────────────────────────────
-- Manager of the subscription programme (or full admin).
CREATE OR REPLACE FUNCTION public.is_sub_manager()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin','sub_manager')
  );
$$;

-- Anyone working the subscription pipeline (manager, kitchen, delivery).
CREATE OR REPLACE FUNCTION public.is_sub_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role IN ('admin','sub_manager','chef','delivery')
  );
$$;

-- ── 2. Tables ────────────────────────────────────────────────────────────────

-- Plans the customer can buy. Fully editable from the admin panel (no code).
CREATE TABLE IF NOT EXISTS public.subscription_plans (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  tagline       TEXT DEFAULT '',
  description   TEXT DEFAULT '',
  price         NUMERIC(10,2) NOT NULL CHECK (price >= 0),
  duration_days INTEGER NOT NULL CHECK (duration_days > 0),
  meals_per_day INTEGER NOT NULL DEFAULT 1 CHECK (meals_per_day > 0),
  features      JSONB NOT NULL DEFAULT '[]'::jsonb,  -- ["Fresh daily", ...]
  badge         TEXT DEFAULT '',                     -- e.g. "MOST POPULAR"
  active        BOOLEAN NOT NULL DEFAULT true,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per purchased subscription.
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id            UUID REFERENCES public.subscription_plans(id),
  -- Member details (filled in the onboarding form after payment)
  customer_name      TEXT DEFAULT '',
  phone              TEXT DEFAULT '',
  email              TEXT DEFAULT '',
  food_preference    TEXT DEFAULT '',   -- veg / non-veg / eggetarian / vegan
  health_goal        TEXT DEFAULT '',   -- weight_loss / muscle_gain / balanced ...
  health_notes       TEXT DEFAULT '',   -- allergies, dislikes, doctor notes
  delivery_address   JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Lifecycle
  status             TEXT NOT NULL DEFAULT 'payment_received'
                     CHECK (status IN ('awaiting_payment','payment_received',
                                       'pending_approval','active','paused',
                                       'rejected','expired','cancelled')),
  start_date         DATE,
  end_date           DATE,
  -- Payment (written by edge functions only)
  razorpay_order_id  TEXT,
  razorpay_payment_id TEXT,
  amount_paid        NUMERIC(10,2),
  -- Provisioning (set on approval)
  auth_user_id       UUID,              -- auth.users id once login is created
  member_code        TEXT,              -- printed on the premium card
  approved_by        TEXT,
  approved_at        TIMESTAMPTZ,
  rejection_reason   TEXT DEFAULT '',
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_subs_status  ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subs_phone   ON public.subscriptions(phone);
CREATE INDEX IF NOT EXISTS idx_subs_user    ON public.subscriptions(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_subs_rzp     ON public.subscriptions(razorpay_order_id);

-- Premium card numbers: MP-0001, MP-0002, …
CREATE SEQUENCE IF NOT EXISTS public.member_code_seq START 1;
CREATE OR REPLACE FUNCTION public.next_member_code()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT 'MP-' || LPAD(nextval('member_code_seq')::text, 4, '0');
$$;
-- Only the service role (edge functions) mints codes.
REVOKE ALL ON FUNCTION public.next_member_code() FROM anon, authenticated;

-- One row per member per meal day. Created by the nightly job; flipped to
-- confirmed/skipped by the member (WhatsApp reply or in-app); then driven
-- through the kitchen by staff.
CREATE TABLE IF NOT EXISTS public.meal_confirmations (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id   UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  meal_date         DATE NOT NULL,
  status            TEXT NOT NULL DEFAULT 'awaiting'
                    CHECK (status IN ('awaiting','confirmed','skipped',
                                      'preparing','prepared','out_for_delivery',
                                      'delivered','missed')),
  menu              JSONB NOT NULL DEFAULT '[]'::jsonb, -- [{name, quantity}] planned items
  priority          INTEGER NOT NULL DEFAULT 0,          -- higher = cook first
  prepared_count    INTEGER NOT NULL DEFAULT 0,          -- meals done (of meals_per_day)
  delivery_agent_id UUID,
  confirmed_via     TEXT DEFAULT '',                     -- whatsapp / app / admin
  confirmed_at      TIMESTAMPTZ,
  prepared_at       TIMESTAMPTZ,
  delivered_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (subscription_id, meal_date)
);
CREATE INDEX IF NOT EXISTS idx_meals_date   ON public.meal_confirmations(meal_date);
CREATE INDEX IF NOT EXISTS idx_meals_status ON public.meal_confirmations(status);

CREATE TABLE IF NOT EXISTS public.delivery_agents (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  phone      TEXT NOT NULL DEFAULT '',
  active     BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meal_agent_fk') THEN
    ALTER TABLE public.meal_confirmations
      ADD CONSTRAINT meal_agent_fk FOREIGN KEY (delivery_agent_id)
      REFERENCES public.delivery_agents(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Promotional banners shown in the customer app. Editable from admin.
CREATE TABLE IF NOT EXISTS public.subscription_banners (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title      TEXT NOT NULL,
  subtitle   TEXT DEFAULT '',
  image_url  TEXT DEFAULT '',
  cta_text   TEXT DEFAULT 'Explore Plans',
  cta_route  TEXT DEFAULT '/subscribe',
  bg_color   TEXT DEFAULT '#1B3A2D',      -- hex, rendered behind text
  active     BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- WhatsApp message templates — the manager edits these in the admin panel,
-- so message wording changes NEVER require a code change.
-- Placeholders: {{name}} {{date}} {{plan}} {{member_code}} {{cutoff_time}}
CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_key TEXT UNIQUE NOT NULL,
  title        TEXT NOT NULL,            -- label shown in the admin editor
  message_text TEXT NOT NULL,
  active       BOOLEAN NOT NULL DEFAULT true,
  updated_by   TEXT DEFAULT '',
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 3. Seed data ─────────────────────────────────────────────────────────────

-- Seed plans only on first run (no unique key on name — guard by emptiness).
INSERT INTO public.subscription_plans
  (name, tagline, description, price, duration_days, meals_per_day, features, badge, sort_order)
SELECT * FROM (VALUES
  ('Weekly Starter', 'Try it for a week',
   'Perfect first step — 7 days of chef-crafted, protein-forward meals delivered to your door.',
   1499, 7, 1,
   '["1 fresh meal every day","Personalised to your health goal","Free home delivery","Pause any day before 9 PM"]'::jsonb,
   '', 1),
  ('Monthly Wellness', 'Our members'' favourite',
   '30 days of consistency — the plan members say changed their routine. Priority kitchen slot and dedicated support.',
   4999, 30, 1,
   '["1 fresh meal every day","Personalised to your health goal","Free priority delivery","Pause any day before 9 PM","Dedicated support on WhatsApp","Save ₹1,000 vs weekly"]'::jsonb,
   'MOST POPULAR', 2),
  ('Monthly Pro', 'Serious about results',
   'Two meals a day for 30 days — full nutrition coverage for training, recovery or transformation goals.',
   8999, 30, 2,
   '["2 fresh meals every day","Macro-tracked portions","Free priority delivery","Pause any day before 9 PM","Dedicated support on WhatsApp","Monthly progress check-in"]'::jsonb,
   'BEST VALUE', 3)
) AS v(name, tagline, description, price, duration_days, meals_per_day, features, badge, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.subscription_plans);

INSERT INTO public.whatsapp_templates (template_key, title, message_text) VALUES
  ('daily_meal_confirm', 'Nightly "meal tomorrow?" question',
   'Hi {{name}} 👋 Your {{plan}} meal for *{{date}}* is being planned.'
   || E'\n\nReply *YES* to confirm tomorrow''s meal or *NO* to skip.'
   || E'\n\nPlease reply before {{cutoff_time}} so our chefs can prepare it fresh for you. 🌱'),
  ('confirm_ack', 'Reply after member confirms',
   'Wonderful, {{name}}! ✅ Your meal for {{date}} is confirmed. Our chefs will have it fresh and on time. See you tomorrow!'),
  ('skip_ack', 'Reply after member skips',
   'No problem, {{name}} — we''ve marked {{date}} as skipped. Rest well, and we''ll check in again tomorrow evening. 💚'),
  ('welcome_member', 'Welcome message on approval',
   'Welcome to the M·PROTI family, {{name}}! 🎉 Your membership {{member_code}} on the {{plan}} plan is now active. Every evening we''ll message you to confirm the next day''s meal. Here''s to your goals! 💪'),
  ('out_for_delivery', 'Meal out for delivery',
   'Hi {{name}}, your meal is on its way! 🛵 It should reach you shortly — enjoy it fresh.')
ON CONFLICT (template_key) DO NOTHING;

INSERT INTO public.subscription_banners (title, subtitle, cta_text, sort_order)
SELECT 'Eat well. Every single day.',
       'Chef-crafted meals matched to your health goal, delivered home. Plans from ₹1,499/week.',
       'See Plans', 1
WHERE NOT EXISTS (SELECT 1 FROM public.subscription_banners);

-- ── 4. Row Level Security ────────────────────────────────────────────────────

ALTER TABLE public.subscription_plans   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meal_confirmations   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_agents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_banners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_templates   ENABLE ROW LEVEL SECURITY;

-- Idempotent re-run: drop our policies first.
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname, tablename FROM pg_policies
           WHERE schemaname='public'
             AND tablename IN ('subscription_plans','subscriptions',
                               'meal_confirmations','delivery_agents',
                               'subscription_banners','whatsapp_templates')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', p.policyname, p.tablename);
  END LOOP;
END $$;

-- Plans: anyone may read ACTIVE plans (the sales page); managers see & edit all.
CREATE POLICY "plans_public_read" ON public.subscription_plans
  FOR SELECT USING (active = true OR public.is_sub_manager());
CREATE POLICY "plans_manager_write" ON public.subscription_plans
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- Subscriptions: NO anon access (all writes flow through edge functions with
-- the service role). Members read their own row; sub staff read; managers write.
CREATE POLICY "subs_member_read" ON public.subscriptions
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid() OR public.is_sub_staff());
CREATE POLICY "subs_manager_write" ON public.subscriptions
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- Meal confirmations: members read their own; staff read; staff update
-- (chef marks prepared, manager assigns agent). Member confirm/skip goes
-- through the confirm_meal() RPC below — never a direct UPDATE.
CREATE POLICY "meals_member_read" ON public.meal_confirmations
  FOR SELECT TO authenticated
  USING (public.is_sub_staff() OR EXISTS (
    SELECT 1 FROM public.subscriptions s
    WHERE s.id = subscription_id AND s.auth_user_id = auth.uid()));
CREATE POLICY "meals_staff_update" ON public.meal_confirmations
  FOR UPDATE TO authenticated
  USING (public.is_sub_staff()) WITH CHECK (public.is_sub_staff());
CREATE POLICY "meals_manager_insert" ON public.meal_confirmations
  FOR INSERT TO authenticated WITH CHECK (public.is_sub_manager());
CREATE POLICY "meals_manager_delete" ON public.meal_confirmations
  FOR DELETE TO authenticated USING (public.is_sub_manager());

-- Delivery agents: staff read, managers manage.
CREATE POLICY "agents_staff_read" ON public.delivery_agents
  FOR SELECT TO authenticated USING (public.is_sub_staff());
CREATE POLICY "agents_manager_write" ON public.delivery_agents
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- Banners: everyone reads active banners; managers manage.
CREATE POLICY "banners_public_read" ON public.subscription_banners
  FOR SELECT USING (active = true OR public.is_sub_manager());
CREATE POLICY "banners_manager_write" ON public.subscription_banners
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- WhatsApp templates: manager-only (the nightly job reads with service role).
CREATE POLICY "templates_manager_all" ON public.whatsapp_templates
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());

-- app_config: the old policies referenced a non-existent admin_users table,
-- locking managers out. Replace with role-based ones (WhatsApp creds editor).
DROP POLICY IF EXISTS "Allow admin read config"   ON public.app_config;
DROP POLICY IF EXISTS "Allow admin update config" ON public.app_config;
DROP POLICY IF EXISTS "config_manager_read"       ON public.app_config;
DROP POLICY IF EXISTS "config_manager_write"      ON public.app_config;
CREATE POLICY "config_manager_read" ON public.app_config
  FOR SELECT TO authenticated USING (public.is_sub_manager());
CREATE POLICY "config_manager_write" ON public.app_config
  FOR ALL TO authenticated
  USING (public.is_sub_manager()) WITH CHECK (public.is_sub_manager());
-- Remove the accidental anon grant from MIGRATION_APP_CONFIG.sql (RLS already
-- blocks it, but least-privilege is cheaper than trust).
REVOKE SELECT ON public.app_config FROM anon;

-- ── 5. Member RPC: confirm / skip tomorrow's meal from the app ──────────────
-- SECURITY DEFINER + auth.uid() → a member can only ever touch their OWN row,
-- and only while it is still awaiting/confirmed/skipped (not in the kitchen).
CREATE OR REPLACE FUNCTION public.confirm_meal(p_meal_date DATE, p_confirm BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sub public.subscriptions%ROWTYPE;
  v_new TEXT := CASE WHEN p_confirm THEN 'confirmed' ELSE 'skipped' END;
BEGIN
  SELECT * INTO v_sub FROM public.subscriptions
  WHERE auth_user_id = auth.uid() AND status = 'active'
  LIMIT 1;
  IF v_sub.id IS NULL THEN
    RAISE EXCEPTION 'No active subscription for this account';
  END IF;
  IF p_meal_date <= CURRENT_DATE THEN
    RAISE EXCEPTION 'Only future meals can be changed';
  END IF;
  IF p_meal_date > COALESCE(v_sub.end_date, p_meal_date) THEN
    RAISE EXCEPTION 'Date is outside your subscription period';
  END IF;

  INSERT INTO public.meal_confirmations (subscription_id, meal_date, status,
                                         confirmed_via, confirmed_at)
  VALUES (v_sub.id, p_meal_date, v_new, 'app', NOW())
  ON CONFLICT (subscription_id, meal_date) DO UPDATE
    SET status = v_new, confirmed_via = 'app', confirmed_at = NOW(),
        updated_at = NOW()
    WHERE meal_confirmations.status IN ('awaiting','confirmed','skipped');
  RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_meal(DATE, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirm_meal(DATE, BOOLEAN) TO authenticated;

-- ── 6. Nightly automation (pg_cron → edge function) ──────────────────────────
-- The edge function creates tomorrow's meal_confirmations rows and sends the
-- WhatsApp question to every active member. 20:00 IST = 14:30 UTC.
--
-- SETUP (one time, in the SQL editor):
--   1. Database → Extensions → enable  pg_cron  and  pg_net.
--   2. Set a strong CRON_SECRET on the edge function:
--        supabase secrets set CRON_SECRET=<long-random-string>
--   3. Replace <CRON_SECRET> below with the same value and run:
--
-- SELECT cron.schedule(
--   'send-daily-meal-whatsapp',
--   '30 14 * * *',
--   $cron$
--   SELECT net.http_post(
--     url     := 'https://pahanghosyepfuwcfexg.supabase.co/functions/v1/send-daily-meal-whatsapp',
--     headers := '{"Content-Type":"application/json","x-cron-secret":"<CRON_SECRET>"}'::jsonb,
--     body    := '{"source":"pg_cron"}'::jsonb
--   );
--   $cron$
-- );
--
-- (The manager can also trigger the same job manually from the admin panel.)

-- ── 7. Staff accounts ────────────────────────────────────────────────────────
-- Subscription manager gets SEPARATE credentials from the main admin:
--   1) Authentication → Users → Add user → email + password + ✅ Auto Confirm.
--   2) INSERT INTO public.profiles (id, email, role)
--      SELECT id, email, 'sub_manager' FROM auth.users
--      WHERE email = 'subscriptions@yourdomain.com'
--      ON CONFLICT (id) DO UPDATE SET role = 'sub_manager';
--
-- Member logins are created automatically by the manager "Approve" button
-- (admin-manage-member edge function) — no SQL needed.
