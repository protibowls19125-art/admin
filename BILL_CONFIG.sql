-- =============================================================================
-- Bill / invoice settings (admin-editable, public-readable so the customer
-- bill can render business name / GST). delivery_charge is also applied
-- server-side to delivery order totals (see razorpay-create-order).
-- =============================================================================

INSERT INTO public.app_config (key, value, description)
VALUES (
  'bill_config',
  '{
     "business_name": "M·PROTI Dining",
     "address": "",
     "gst_number": "",
     "gst_percent": 5,
     "delivery_charge": 0,
     "footer": "Thank you for your order!"
   }'::jsonb,
  'Invoice header + GST % (inclusive) + delivery charge.'
)
ON CONFLICT (key) DO NOTHING;

DROP POLICY IF EXISTS "app_config_public_read" ON public.app_config;
CREATE POLICY "app_config_public_read" ON public.app_config
  FOR SELECT TO anon, authenticated
  USING (key IN ('service_hours','thermal_printer_config','support_contact','bill_config'));
