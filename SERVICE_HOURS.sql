-- =============================================================================
-- Service hours: per order-type availability windows (dine_in / takeaway /
-- delivery). Stored in app_config; set in the admin panel; read by the
-- customer app to gate which order types can be ordered right now.
--
-- Also fixes app_config RLS (the old policies referenced a non-existent
-- admin_users table). Public can read ONLY safe keys (hours + printer);
-- secrets like whatsapp_credentials stay admin-only.
-- =============================================================================

-- Create the config table if it was never set up.
CREATE TABLE IF NOT EXISTS public.app_config (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key         VARCHAR(100) UNIQUE NOT NULL,
  value       JSONB NOT NULL,
  description TEXT,
  updated_by  VARCHAR(255),
  updated_at  TIMESTAMP DEFAULT NOW(),
  created_at  TIMESTAMP DEFAULT NOW()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='app_config'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.app_config;', p.policyname);
  END LOOP;
END $$;

-- Public can read only non-sensitive config keys.
CREATE POLICY "app_config_public_read" ON public.app_config
  FOR SELECT TO anon, authenticated
  USING (key IN ('service_hours', 'thermal_printer_config'));

-- Admins manage all config.
CREATE POLICY "app_config_admin" ON public.app_config
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Default hours (kept if already set).
INSERT INTO public.app_config (key, value, description)
VALUES (
  'service_hours',
  '{
     "dine_in":  {"enabled": true, "open": "09:00", "close": "21:00"},
     "takeaway": {"enabled": true, "open": "09:00", "close": "21:00"},
     "delivery": {"enabled": true, "open": "10:00", "close": "20:00"}
   }'::jsonb,
  'Per order-type availability windows (24h HH:mm local time).'
)
ON CONFLICT (key) DO NOTHING;
