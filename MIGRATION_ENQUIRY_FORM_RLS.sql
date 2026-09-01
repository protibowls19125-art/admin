-- Fix: add subscription_enquiry_form_url to the public-read allowlist
-- so the user app can read the Google Form URL.
-- Run in Supabase SQL Editor.

DROP POLICY IF EXISTS app_config_public_read ON public.app_config;
CREATE POLICY app_config_public_read ON public.app_config
  FOR SELECT USING (key IN (
    'service_hours', 'thermal_printer_config', 'support_contact',
    'bill_config', 'menu_featured_label', 'subscription_enquiry_form_url'
  ));
