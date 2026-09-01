-- =============================================================================
-- Support contact for the customer FAQ page (admin-editable, public-readable).
-- =============================================================================

INSERT INTO public.app_config (key, value, description)
VALUES (
  'support_contact',
  '{"phone": "", "hours_note": ""}'::jsonb,
  'Customer support phone shown on the FAQ / Help page.'
)
ON CONFLICT (key) DO NOTHING;

-- Let the customer app read it (add support_contact to the public-read keys).
DROP POLICY IF EXISTS "app_config_public_read" ON public.app_config;
CREATE POLICY "app_config_public_read" ON public.app_config
  FOR SELECT TO anon, authenticated
  USING (key IN ('service_hours', 'thermal_printer_config', 'support_contact'));
