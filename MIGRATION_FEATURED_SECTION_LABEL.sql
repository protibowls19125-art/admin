-- One-time migration: the customer home page's featured-items section title
-- ("FEATURED CREATION") becomes admin-editable instead of hardcoded text.
--
-- Run once in the Supabase SQL Editor.

INSERT INTO public.app_config (key, value, description, updated_at)
VALUES (
  'menu_featured_label',
  '{"label": "TODAY''S SPECIAL"}'::jsonb,
  'Section title above the featured-items hero on the customer app home page',
  now()
)
ON CONFLICT (key) DO NOTHING;

-- app_config's public-read policy is allowlisted to specific keys — add this
-- one so the (anonymous) customer app can actually read it.
DROP POLICY IF EXISTS app_config_public_read ON public.app_config;
CREATE POLICY app_config_public_read ON public.app_config
  FOR SELECT USING (key IN (
    'service_hours', 'thermal_printer_config', 'support_contact',
    'bill_config', 'menu_featured_label'
  ));
